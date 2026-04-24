// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function envUint(string calldata key) external returns (uint256);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract LocalTestUSDC is ERC20 {
    constructor(address receiver, uint256 initialSupply) ERC20("Local Test USDC", "lUSDC") {
        _mint(receiver, initialSupply);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @notice Deploys a local 6-decimal ERC-20 for Anvil settlement rehearsals.
contract DeployLocalTestUSDC {
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;
    uint256 internal constant INITIAL_SUPPLY = 1_000_000_000_000;

    error UnexpectedChainId(uint256 expected, uint256 actual);

    function run() external returns (LocalTestUSDC deployed) {
        if (block.chainid != ANVIL_CHAIN_ID) {
            revert UnexpectedChainId(ANVIL_CHAIN_ID, block.chainid);
        }

        uint256 deployerKey = VM.envUint("ANVIL_PRIVATE_KEY");
        address receiver = VM.addr(deployerKey);

        VM.startBroadcast(deployerKey);
        deployed = new LocalTestUSDC(receiver, INITIAL_SUPPLY);
        VM.stopBroadcast();
    }
}
