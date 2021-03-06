pragma solidity =0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";


contract EIP712Base {
    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
    }

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));

    bytes32 internal domainSeparator;

    constructor(string memory name, string memory version) public {
        uint chainId;
        assembly {
            chainId := chainid()
        }

        domainSeparator = keccak256(abi.encode(
          EIP712_DOMAIN_TYPEHASH,
          keccak256(bytes(name)),
          keccak256(bytes(version)),
          chainId,
          address(this)
        ));
    }

    function getDomainSeparator() private view returns(bytes32) {
		    return domainSeparator;
	  }

    /**
    * Accept message hash and returns hash message in EIP712 compatible form
    * So that it can be used to recover signer from signature signed using EIP712 formatted data
    * https://eips.ethereum.org/EIPS/eip-712
    * "\\x19" makes the encoding deterministic
    * "\\x01" is the version byte to make it compatible to EIP-191
    */
    function toTypedMessageHash(bytes32 messageHash) internal view returns(bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), messageHash));
    }

}

contract EIP712MetaTransaction is EIP712Base('Sun coin proxy', '1') {
    using SafeMath for uint256;

    bytes32 private constant META_TRANSACTION_TYPEHASH = keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionSignature)"));
    mapping(address => uint256) private _nonces;

    event MetaTransactionExecuted(address userAddress, address relayerAddress, bytes functionSignature);

    /*
     * Meta transaction structure.
     * No point of including value field here as if user is doing value transfer then he has the funds to pay for gas
     * He should call the desired function directly in that case.
     */
    struct MetaTransaction {
        uint256 nonce;
        address from;
        bytes functionSignature;
    }

    function executeMetaTransaction(
        address userAddress,
        bytes memory functionSignature,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable returns (bytes memory) {
        _preMetaTxValidation(userAddress);

        MetaTransaction memory metaTx = MetaTransaction({
            nonce: _nonces[userAddress],
            from: userAddress,
            functionSignature: functionSignature
        });
        require(verify(userAddress, metaTx, v, r, s), "Signer and signature do not match");

        // Append userAddress and relayer address at the end to extract it from calling context
        (bool success, bytes memory returnData) = address(this).call(abi.encodePacked(functionSignature, userAddress));
        require(success, "Function call not successful");

        _nonces[userAddress] = _nonces[userAddress].add(1);

        emit MetaTransactionExecuted(userAddress, msg.sender, functionSignature);

        return returnData;
    }

    function hashMetaTransaction(MetaTransaction memory metaTx) internal pure returns (bytes32) {
		    return keccak256(abi.encode(
            META_TRANSACTION_TYPEHASH,
            metaTx.nonce,
            metaTx.from,
            keccak256(metaTx.functionSignature)
        ));
	  }

    function nonces(address user) public view returns(uint256 n) {
        n = _nonces[user];
    }

    function verify(address signer, MetaTransaction memory metaTx, uint8 v, bytes32 r, bytes32 s) internal view returns (bool) {
        return signer == ecrecover(toTypedMessageHash(hashMetaTransaction(metaTx)), v, r, s);
    }

    function msgSender() internal view returns(address sender) {
        if(msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(mload(add(array, index)), 0xffffffffffffffffffffffffffffffffffffffff)
            }
        } else {
            sender = msg.sender;
        }
        return sender;
    }

    function _preMetaTxValidation(address sender) internal virtual { }
}