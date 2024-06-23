// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";



contract AtomicSwap is EIP712, Nonces {
    using SafeERC20 for IERC20;

    struct Swap {
        address ownerA;
        address ownerB;
        address tokenA;
        address tokenB;
        uint256 valueA;
        uint256 valueB;
        // uint256 nonceOwnerA;
        // uint256 nonceOwnerB;
        uint256 deadline;
    }

    bytes32 private constant SWAP_TYPEHASH =
        keccak256("Swap(address ownerA,address ownerB,address tokenA,address tokenB,uint256 valueA,uint256 valueB,uint256 nonceOwnerA,uint256 nonceOwnerB,uint256 deadline)");

    /**
     * @dev Permit deadline has expired.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev Mismatched signature.
     */
    error ERC2612InvalidSigner(address signer, address owner);

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC20 swap name.
     */
    constructor(string memory name) EIP712(name, "1") {}

    function run(Swap memory swap, bytes memory sigA, bytes memory sigB) public {
        if (block.timestamp > swap.deadline) {
            revert ERC2612ExpiredSignature(swap.deadline);
        }

        bytes32 structHash = keccak256(abi.encode(
            SWAP_TYPEHASH,
            swap.ownerA,
            swap.ownerB,
            swap.tokenA,
            swap.tokenB,
            swap.valueA,
            swap.valueB,
            _useNonce(swap.ownerA),
            _useNonce(swap.ownerB),
            swap.deadline
        ));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signerA = ECDSA.recover(hash, sigA);
        if (signerA != swap.ownerA) {
            revert ERC2612InvalidSigner(signerA, swap.ownerA);
        }
        address signerB = ECDSA.recover(hash, sigB);
        if (signerB != swap.ownerB) {
            revert ERC2612InvalidSigner(signerB, swap.ownerB);
        }

        IERC20(swap.tokenA).safeTransferFrom(swap.ownerA, swap.ownerB, swap.valueA);
        IERC20(swap.tokenB).safeTransferFrom(swap.ownerB, swap.ownerA, swap.valueB);
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }
}