// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Interface of the LoanStreamChain implementation.
/// @dev Adjust constructor signature to match your LoanStreamChain.sol.
interface ILoanStreamChain {
    // example: constructor(address _admin, address _loanToken, address _collateralToken, address _oracle);
}

contract LoanStreamChainDeployer {
    event LoanStreamChainDeployed(address indexed loanStreamChain, address indexed deployer);

    /// @notice Deploy a new LoanStreamChain instance.
    /// @dev Replace parameters and the `new LoanStreamChain(...)` call
    ///      to match your real constructor.
    function deployLoanStreamChain(
        address admin,
        address loanToken,
        address collateralToken,
        address priceOracle
    ) external returns (address) {
        require(admin != address(0), "Invalid admin");
        require(loanToken != address(0), "Invalid loan token");
        require(collateralToken != address(0), "Invalid collateral token");
        require(priceOracle != address(0), "Invalid oracle");

        LoanStreamChain loanStreamChain = new LoanStreamChain(
            admin,
            loanToken,
            collateralToken,
            priceOracle
        );

        emit LoanStreamChainDeployed(address(loanStreamChain), msg.sender);
        return address(loanStreamChain);
    }
}

/// @dev Stub for the real LoanStreamChain contract.
/// In your project, delete this and instead:
/// `import "./LoanStreamChain.sol";`
contract LoanStreamChain {
    address public admin;
    address public loanToken;
    address public collateralToken;
    address public priceOracle;

    constructor(
        address _admin,
        address _loanToken,
        address _collateralToken,
        address _priceOracle
    ) {
        admin = _admin;
        loanToken = _loanToken;
        collateralToken = _collateralToken;
        priceOracle = _priceOracle;
    }
}
