// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Well first things first, since the task asks for oneoff tx with multiple signers, I'll stick with the same structure as the AtomicSwap
// Since we have to deal with multiple txs let's stick with arraifyed Action struct. (Easier to encode for typehash)
// minSignature i'll keep seperately, and assume it can be changed by another action via delegateCall
// We could have an erc721/erc1155 but let's keep things simple for now.
contract MultiSig is EIP712, Nonces {

    uint256 public _minSignatures; 
    mapping (address => bool) public members;
    mapping (address => bool) internal _hasVoted;

    enum ActionType {
        Call, // 0
        DelegateCall, // 1
        StaticCall // 2
    }

    struct Actions {
        address[] target;
        uint8[] actionType;
        uint256[] value;
        bytes[] payload;
        address[] signers;
        // uint256[] nonceOfSigner;
        uint256 deadline;
    }

    bytes32 private constant ACTION_TYPEHASH = keccak256("Action(address[] target,uint8[] actionType,uint256[] value,bytes[] payload,address[] signers,uint256[] nonceOfSigner,uint256 deadline)");

    /**
     * @dev Permit deadline has expired.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev Mismatched signature.
     */
    error ERC2612InvalidSigner(address signer, address owner);

    /**
     * @dev Unsufficient signers
     */
    error MultiSigUnsufficientSignatures(uint256 signatures, uint256 minSignatures);

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC20 swap name.
     */
    constructor(string memory name, address[] memory initMembers, uint256 minSignatures) EIP712(name, "1") {
        require(initMembers.length > 0 && minSignatures <= initMembers.length);

        for (uint256 i = 0; i < initMembers.length; i++) {
            members[initMembers[i]] = true;
        }
        _minSignatures = minSignatures;
    }

    /**
     * @dev This runs a swap on two ERC20 tokens
     * Note: since the assignment asked for ERC20, ERC20Permit tokens are not considered, thus allowance should be setup beforehand.
     */
    function run(Actions memory actions, bytes[] memory signatures) public {
        if (block.timestamp > actions.deadline) {
            revert ERC2612ExpiredSignature(actions.deadline);
        }

        uint256[] memory signerNonces = new uint256[](actions.signers.length);
        if (signatures.length < _minSignatures || signatures.length != actions.signers.length) {
            revert MultiSigUnsufficientSignatures(signatures.length, _minSignatures);
        }
        for (uint256 i = 0; i < signatures.length; i++) {
            if (_hasVoted[actions.signers[i]]) {
                revert MultiSigUnsufficientSignatures(signatures.length, _minSignatures);
            }
            signerNonces[i] = _useNonce(actions.signers[i]);
            _hasVoted[actions.signers[i]] = true;
        }

        bytes32 structHash = keccak256(abi.encode(
            ACTION_TYPEHASH,
            actions.target,
            actions.actionType,
            actions.value,
            actions.payload,
            actions.signers,
            signerNonces,
            actions.deadline
        ));

        bytes32 hash = _hashTypedDataV4(structHash);

        for (uint256 i = 0; i < signatures.length; i++) { 
            address signer = ECDSA.recover(hash, signatures[i]);
            if (signer != actions.signers[i]) {
                revert ERC2612InvalidSigner(signer, actions.signers[i]);
            }
        }

        for (uint256 i = 0; i < signatures.length; i++) { 
            delete _hasVoted[actions.signers[i]];
        }

        for (uint256 i = 0; i < actions.target.length; i++) {
            ActionType s = ActionType(actions.actionType[i]);
            if (s == ActionType.Call) {
                (bool success, bytes memory returnData) = address(actions.target[i]).call{ value: actions.value[i] }(actions.payload[i]);
                require(success);
            } else if (s == ActionType.DelegateCall) {
                (bool success, bytes memory returnData) = address(actions.target[i]).delegatecall(actions.payload[i]);
                require(success);
            } else if (s == ActionType.StaticCall) {
                (bool success, bytes memory returnData) = address(actions.target[i]).staticcall(actions.payload[i]);
                require(success);
            }
        }
    }
}