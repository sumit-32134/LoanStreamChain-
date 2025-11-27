// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LoanStream Chain
 * @dev A decentralized lending and borrowing protocol with streaming loan capabilities
 * @notice This contract enables users to deposit collateral, borrow assets, and repay loans
 */
contract Project {
    
    // State Variables
    address public owner;
    uint256 public collateralFactor; // Percentage of collateral value that can be borrowed (in basis points, e.g., 7500 = 75%)
    uint256 public liquidationThreshold; // Threshold for liquidation (in basis points, e.g., 8500 = 85%)
    uint256 public baseInterestRate; // Base annual interest rate (in basis points, e.g., 500 = 5%)
    uint256 public totalLiquidity; // Total liquidity available in the protocol
    uint256 public totalBorrowed; // Total amount currently borrowed
    
    // Structs
    struct Loan {
        uint256 principal; // Original loan amount
        uint256 collateral; // Collateral amount deposited
        uint256 interestAccrued; // Interest accumulated
        uint256 startTime; // Timestamp when loan was taken
        uint256 lastUpdateTime; // Last time interest was calculated
        bool isActive; // Loan status
    }
    
    struct LenderInfo {
        uint256 depositAmount; // Amount deposited by lender
        uint256 depositTime; // Time of deposit
        uint256 interestEarned; // Interest earned by lender
    }
    
    // Mappings
    mapping(address => uint256) public collateralBalances; // User collateral balances
    mapping(address => Loan) public loans; // User active loans
    mapping(address => LenderInfo) public lenders; // Lender information
    mapping(address => bool) public isWhitelisted; // Whitelisted addresses for enhanced features
    
    // Events
    event CollateralDeposited(address indexed user, uint256 amount, uint256 timestamp);
    event CollateralWithdrawn(address indexed user, uint256 amount, uint256 timestamp);
    event LoanIssued(address indexed borrower, uint256 loanAmount, uint256 collateralAmount, uint256 timestamp);
    event LoanRepaid(address indexed borrower, uint256 amount, uint256 interestPaid, uint256 timestamp);
    event LoanLiquidated(address indexed borrower, uint256 collateralSeized, uint256 timestamp);
    event LiquidityAdded(address indexed lender, uint256 amount, uint256 timestamp);
    event LiquidityWithdrawn(address indexed lender, uint256 amount, uint256 interest, uint256 timestamp);
    event CollateralFactorUpdated(uint256 newFactor, uint256 timestamp);
    event InterestRateUpdated(uint256 newRate, uint256 timestamp);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier hasActiveLoan() {
        require(loans[msg.sender].isActive, "No active loan found");
        _;
    }
    
    modifier noActiveLoan() {
        require(!loans[msg.sender].isActive, "Active loan exists, repay first");
        _;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;
        collateralFactor = 7500; // 75% LTV ratio
        liquidationThreshold = 8500; // 85% liquidation threshold
        baseInterestRate = 500; // 5% annual interest rate
    }
    
    /**
     * @dev Allows lenders to add liquidity to the protocol
     * @notice Lenders earn interest on their deposited funds
     */
    function addLiquidity() external payable {
        require(msg.value > 0, "Must deposit non-zero amount");
        
        if (lenders[msg.sender].depositAmount > 0) {
            _updateLenderInterest(msg.sender);
        }
        
        lenders[msg.sender].depositAmount += msg.value;
        lenders[msg.sender].depositTime = block.timestamp;
        totalLiquidity += msg.value;
        
        emit LiquidityAdded(msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Allows lenders to withdraw their liquidity and earned interest
     */
    function withdrawLiquidity() external {
        require(lenders[msg.sender].depositAmount > 0, "No liquidity deposited");
        require(totalLiquidity - totalBorrowed >= lenders[msg.sender].depositAmount, "Insufficient available liquidity");
        
        _updateLenderInterest(msg.sender);
        
        uint256 withdrawAmount = lenders[msg.sender].depositAmount;
        uint256 interestEarned = lenders[msg.sender].interestEarned;
        uint256 totalWithdraw = withdrawAmount + interestEarned;
        
        lenders[msg.sender].depositAmount = 0;
        lenders[msg.sender].interestEarned = 0;
        totalLiquidity -= withdrawAmount;
        
        (bool success, ) = payable(msg.sender).call{value: totalWithdraw}("");
        require(success, "Transfer failed");
        
        emit LiquidityWithdrawn(msg.sender, withdrawAmount, interestEarned, block.timestamp);
    }
    
    /**
     * @dev Allows users to deposit collateral
     */
    function depositCollateral() external payable {
        require(msg.value > 0, "Collateral must be greater than zero");
        
        collateralBalances[msg.sender] += msg.value;
        
        emit CollateralDeposited(msg.sender, msg.value, block.timestamp);
    }
    
    /**
     * @dev Allows users to withdraw available collateral
     * @param amount Amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(collateralBalances[msg.sender] >= amount, "Insufficient collateral balance");
        
        if (loans[msg.sender].isActive) {
            uint256 lockedCollateral = loans[msg.sender].collateral;
            require(collateralBalances[msg.sender] - amount >= lockedCollateral, "Cannot withdraw locked collateral");
        }
        
        collateralBalances[msg.sender] -= amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit CollateralWithdrawn(msg.sender, amount, block.timestamp);
    }
    
    /**
     * @dev Allows users to borrow against their collateral
     * @param loanAmount Amount to borrow
     */
    function borrow(uint256 loanAmount) external noActiveLoan {
        require(loanAmount > 0, "Loan amount must be greater than zero");
        require(collateralBalances[msg.sender] > 0, "No collateral deposited");
        
        uint256 maxBorrowAmount = (collateralBalances[msg.sender] * collateralFactor) / 10000;
        require(loanAmount <= maxBorrowAmount, "Loan amount exceeds borrowing capacity");
        require(totalLiquidity - totalBorrowed >= loanAmount, "Insufficient protocol liquidity");
        
        loans[msg.sender] = Loan({
            principal: loanAmount,
            collateral: collateralBalances[msg.sender],
            interestAccrued: 0,
            startTime: block.timestamp,
            lastUpdateTime: block.timestamp,
            isActive: true
        });
        
        totalBorrowed += loanAmount;
        
        (bool success, ) = payable(msg.sender).call{value: loanAmount}("");
        require(success, "Transfer failed");
        
        emit LoanIssued(msg.sender, loanAmount, collateralBalances[msg.sender], block.timestamp);
    }
    
    /**
     * @dev Allows borrowers to repay their loans
     */
    function repayLoan() external payable hasActiveLoan {
        _updateLoanInterest(msg.sender);
        
        Loan storage loan = loans[msg.sender];
        uint256 totalDebt = loan.principal + loan.interestAccrued;
        
        require(msg.value > 0, "Repayment amount must be greater than zero");
        require(msg.value <= totalDebt, "Repayment exceeds debt");
        
        uint256 interestPaid = 0;
        
        if (msg.value >= totalDebt) {
            // Full repayment
            interestPaid = loan.interestAccrued;
            totalBorrowed -= loan.principal;
            loan.principal = 0;
            loan.interestAccrued = 0;
            loan.isActive = false;
        } else {
            // Partial repayment
            if (msg.value <= loan.interestAccrued) {
                loan.interestAccrued -= msg.value;
                interestPaid = msg.value;
            } else {
                uint256 principalPayment = msg.value - loan.interestAccrued;
                interestPaid = loan.interestAccrued;
                loan.interestAccrued = 0;
                loan.principal -= principalPayment;
                totalBorrowed -= principalPayment;
            }
            loan.lastUpdateTime = block.timestamp;
        }
        
        emit LoanRepaid(msg.sender, msg.value, interestPaid, block.timestamp);
    }
    
    /**
     * @dev Checks if a loan is eligible for liquidation
     * @param borrower Address of the borrower
     */
    function isLiquidatable(address borrower) public view returns (bool) {
        if (!loans[borrower].isActive) return false;
        
        uint256 totalDebt = loans[borrower].principal + _calculateInterest(borrower);
        uint256 collateralValue = loans[borrower].collateral;
        uint256 liquidationValue = (collateralValue * liquidationThreshold) / 10000;
        
        return totalDebt >= liquidationValue;
    }
    
    /**
     * @dev Liquidates an undercollateralized loan
     * @param borrower Address of the borrower to liquidate
     */
    function liquidateLoan(address borrower) external {
        require(loans[borrower].isActive, "No active loan to liquidate");
        require(isLiquidatable(borrower), "Loan is not eligible for liquidation");
        
        Loan storage loan = loans[borrower];
        uint256 collateralToSeize = loan.collateral;
        
        collateralBalances[borrower] -= collateralToSeize;
        totalBorrowed -= loan.principal;
        
        loan.principal = 0;
        loan.collateral = 0;
        loan.interestAccrued = 0;
        loan.isActive = false;
        
        // Transfer seized collateral to liquidator (could be enhanced with liquidation rewards)
        (bool success, ) = payable(msg.sender).call{value: collateralToSeize}("");
        require(success, "Transfer failed");
        
        emit LoanLiquidated(borrower, collateralToSeize, block.timestamp);
    }
    
    /**
     * @dev Updates the interest accrued for a loan
     * @param borrower Address of the borrower
     */
    function _updateLoanInterest(address borrower) internal {
        if (!loans[borrower].isActive) return;
        
        uint256 interest = _calculateInterest(borrower);
        loans[borrower].interestAccrued += interest;
        loans[borrower].lastUpdateTime = block.timestamp;
    }
    
    /**
     * @dev Calculates interest for a loan
     * @param borrower Address of the borrower
     */
    function _calculateInterest(address borrower) internal view returns (uint256) {
        Loan memory loan = loans[borrower];
        if (!loan.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - loan.lastUpdateTime;
        uint256 annualInterest = (loan.principal * baseInterestRate) / 10000;
        uint256 interest = (annualInterest * timeElapsed) / 365 days;
        
        return interest;
    }
    
    /**
     * @dev Updates interest earned by a lender
     * @param lender Address of the lender
     */
    function _updateLenderInterest(address lender) internal {
        if (lenders[lender].depositAmount == 0) return;
        
        uint256 timeElapsed = block.timestamp - lenders[lender].depositTime;
        uint256 annualInterest = (lenders[lender].depositAmount * baseInterestRate) / 10000;
        uint256 interest = (annualInterest * timeElapsed) / 365 days;
        
        lenders[lender].interestEarned += interest;
        lenders[lender].depositTime = block.timestamp;
    }
    
    /**
     * @dev Returns the current debt of a borrower
     * @param borrower Address of the borrower
     */
    function getCurrentDebt(address borrower) external view returns (uint256) {
        if (!loans[borrower].isActive) return 0;
        
        uint256 currentInterest = _calculateInterest(borrower);
        return loans[borrower].principal + loans[borrower].interestAccrued + currentInterest;
    }
    
    /**
     * @dev Returns the maximum borrowable amount for a user
     * @param user Address of the user
     */
    function getMaxBorrowAmount(address user) external view returns (uint256) {
        if (loans[user].isActive) return 0;
        
        uint256 maxBorrow = (collateralBalances[user] * collateralFactor) / 10000;
        uint256 availableLiquidity = totalLiquidity - totalBorrowed;
        
        return maxBorrow > availableLiquidity ? availableLiquidity : maxBorrow;
    }
    
    /**
     * @dev Owner function to update collateral factor
     * @param newFactor New collateral factor (in basis points)
     */
    function setCollateralFactor(uint256 newFactor) external onlyOwner {
        require(newFactor > 0 && newFactor <= 9000, "Invalid collateral factor");
        collateralFactor = newFactor;
        emit CollateralFactorUpdated(newFactor, block.timestamp);
    }
    
    /**
     * @dev Owner function to update base interest rate
     * @param newRate New interest rate (in basis points)
     */
    function setInterestRate(uint256 newRate) external onlyOwner {
        require(newRate > 0 && newRate <= 5000, "Invalid interest rate");
        baseInterestRate = newRate;
        emit InterestRateUpdated(newRate, block.timestamp);
    }
    
    /**
     * @dev Owner function to update liquidation threshold
     * @param newThreshold New liquidation threshold (in basis points)
     */
    function setLiquidationThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > collateralFactor && newThreshold <= 9500, "Invalid threshold");
        liquidationThreshold = newThreshold;
    }
    
    /**
     * @dev Get protocol statistics
     */
    function getProtocolStats() external view returns (
        uint256 _totalLiquidity,
        uint256 _totalBorrowed,
        uint256 _availableLiquidity,
        uint256 _utilizationRate
    ) {
        _totalLiquidity = totalLiquidity;
        _totalBorrowed = totalBorrowed;
        _availableLiquidity = totalLiquidity - totalBorrowed;
        _utilizationRate = totalLiquidity > 0 ? (totalBorrowed * 10000) / totalLiquidity : 0;
    }
    
    // Fallback and receive functions
    receive() external payable {
        revert("Use addLiquidity or depositCollateral functions");
    }
    
    fallback() external payable {
        revert("Function does not exist");
    }
}
