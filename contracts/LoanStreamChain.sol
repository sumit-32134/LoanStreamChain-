State Variables
    address public owner;
    uint256 public collateralFactor; Threshold for liquidation (in basis points, e.g., 8500 = 85%)
    uint256 public baseInterestRate; Total liquidity available in the protocol
    uint256 public totalBorrowed; Structs
    struct Loan {
        uint256 principal; Collateral amount deposited
        uint256 interestAccrued; Timestamp when loan was taken
        uint256 lastUpdateTime; Loan status
    }
    
    struct LenderInfo {
        uint256 depositAmount; Time of deposit
        uint256 interestEarned; Mappings
    mapping(address => uint256) public collateralBalances; User active loans
    mapping(address => LenderInfo) public lenders; Whitelisted addresses for enhanced features
    
    Modifiers
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
    
    75% LTV ratio
        liquidationThreshold = 8500; 5% annual interest rate
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
            Partial repayment
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
        
        Fallback and receive functions
    receive() external payable {
        revert("Use addLiquidity or depositCollateral functions");
    }
    
    fallback() external payable {
        revert("Function does not exist");
    }
}
// 
Contract End
// 
