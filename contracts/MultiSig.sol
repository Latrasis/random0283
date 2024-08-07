// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Well first things first, since the task asks for oneoff tx with multiple signers, I'll stick with the same structure as the AtomicSwap
// Since we have to deal with multiple txs let's stick with arraifyed Action struct. (Easier to encode for typehash)
// minSignature i'll keep seperately, and assume it can be changed by another action via delegateCall
// We could have an erc721/erc1155 but let's keep things simple for now.
contract MultiSig is EIP712, Nonces {
    uint256 public _minSignatures;
    mapping(address => bool) public _members;
    using Address for address;

    enum ActionType {
        Call, // 0
        DelegateCall, // 1
        StaticCall // 2
    }

    struct Actions {
        Action[] list;
        address[] signers;
        // uint256[] nonceOfSigner;
        uint256 deadline;
    }

    struct Action {
        uint8 actionType;
        address target;
        uint256 value;
        bytes payload;
    }

    bytes32 private constant ACTIONS_TYPEHASH =
        keccak256(
            "Actions(Action[] list,address[] signers,uint256[] nonceOfSigner,uint256 deadline)Action(uint8 actionType,address target,uint256 value,bytes payload)"
        );
    bytes32 private constant ACTION_TYPEHASH =
        keccak256(
            "Action(uint8 actionType,address target,uint256 value,bytes payload)"
        );

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
    error MultiSigUnsufficientSignatures(
        uint256 signatures,
        uint256 minSignatures
    );

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC20 swap name.
     */
    constructor(
        string memory name,
        address[] memory initMembers,
        uint256 minSigs
    ) EIP712(name, "1") {
        require(initMembers.length > 0 && minSigs <= initMembers.length);

        for (uint256 i = 0; i < initMembers.length; i++) {
            _members[initMembers[i]] = true;
        }
        _minSignatures = minSigs;
    }

    function encodeAction(Action memory action) internal pure returns (bytes memory) {
        return abi.encode(
            ACTION_TYPEHASH,
            action.actionType,
            action.target,
            action.value,
            keccak256(abi.encodePacked(action.payload))
        );
    
    }
    function encodeActions(
        Actions memory actions,
        uint256[] memory signerNonces
    ) public returns (bytes memory) {
        bytes32[] memory encodeData = new bytes32[](actions.list.length);
        for (uint i; i < actions.list.length; ++i) {
            encodeData[i] = keccak256(encodeAction(actions.list[i]));
        }

        return
            abi.encode(
                ACTIONS_TYPEHASH,
                keccak256(abi.encodePacked(encodeData)),
                keccak256(abi.encodePacked(actions.signers)),
                keccak256(abi.encodePacked(signerNonces)),
                actions.deadline
            );
    }

    /**
     * @dev This runs a swap on two ERC20 tokens
     * Note: since the assignment asked for ERC20, ERC20Permit tokens are not considered, thus allowance should be setup beforehand.
     * To prevent duplicates actions.signers MUST be ordered
     */
    function run(Actions memory actions, bytes[] memory signatures) public payable {
        if (block.timestamp > actions.deadline) {
            revert ERC2612ExpiredSignature(actions.deadline);
        }

        uint256[] memory signerNonces = new uint256[](actions.signers.length);
        if (
            signatures.length < _minSignatures ||
            signatures.length != actions.signers.length
        ) {
            revert MultiSigUnsufficientSignatures(
                signatures.length,
                _minSignatures
            );
        }
        for (uint256 i = 0; i < actions.signers.length; i++) {
            if (i > 0 && (actions.signers[i - 1] >= actions.signers[i])) {
                revert MultiSigUnsufficientSignatures(
                    signatures.length,
                    _minSignatures
                );
            }
            if (!_members[actions.signers[i]]) {
                revert ERC2612InvalidSigner(address(0), actions.signers[i]);
            }
            signerNonces[i] = _useNonce(actions.signers[i]);
        }

        bytes32 structHash = keccak256(encodeActions(actions, signerNonces));

        bytes32 hash = _hashTypedDataV4(structHash);

        for (uint256 k = 0; k < signatures.length; k++) {
            address signer = ECDSA.recover(hash, signatures[k]);
            if (signer != actions.signers[k]) {
                revert ERC2612InvalidSigner(signer, actions.signers[k]);
            }
        }

        for (uint256 i = 0; i < actions.list.length; i++) {
            Action memory a = actions.list[i];
            if (ActionType(a.actionType) == ActionType.Call) {
                a.target.functionCallWithValue(a.payload, a.value);
            } else if (ActionType(a.actionType) == ActionType.DelegateCall) {
                a.target.functionDelegateCall(a.payload);
            } else if (ActionType(a.actionType) == ActionType.StaticCall) {
                a.target.functionStaticCall(a.payload);
            }
        }
    }
}
