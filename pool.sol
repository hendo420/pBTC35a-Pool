pragma solidity ^0.5.0;

interface Uniswap{
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts); //calldata path = tokenA address, tokenB address
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface Staking {
    function stake(uint256 amount) external;
    function exit() external;
    function getIncome() external;
    function incomeEarned(address account) external view returns (uint256);
}

library SafeMath {
    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }
}

contract pool {
    using SafeMath for uint;
    
    address Unifactory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;//rinkeby
    address Unirouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;//rinkeby
    address stakingAddress = 0xd14140FEd55f9D68c52976DF2AaA00479b1D2B10;//rinkeby
    address pBTC35aAddress = 0x21d73E27828a8B013Fca86f8C7967d19B94c10Cc;//rinkeby
    address wBTCAddress = 0xaB902295Fa1C5A968C335C789a0555C5d3aD2187;//rinkeby
    address marsAddress;
    
    address public dev;
    uint minBalance = 1;
    
    mapping (address => uint) public LP;
    uint public pBTC35aStaked = 0;
    
    constructor () public{
        dev = msg.sender;
    }
    
    /*====================================Admin================================*/
    
    function setAddress(address _unifactory, address _unirouter, address _stakingAddress, address _pBTC35aAddress, address _wBTCAddress) public returns(bool){
        Unifactory = _unifactory;
        Unirouter = _unirouter;
        stakingAddress = _stakingAddress;
        pBTC35aAddress = _pBTC35aAddress;
        wBTCAddress = _wBTCAddress;
        return true;
    }
    
    function setMinBalance(uint _minBalance) public returns(bool) {
        require(msg.sender == dev);
        minBalance = _minBalance;
        return true;
    }
    
    /*====================================ERC20================================*/
    event Mint(address indexed sender, uint amount);
    event Burn(address indexed sender, uint amount);
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    
    mapping (address => uint) public balance;
    mapping(address => mapping(address => uint)) public allowance;
    uint COIN = 10**18;
    
    string public constant name = 'pBTC35a Pool';
    string public constant symbol = 'MP-V1';
    uint8 public constant decimals = 18;
    
    uint _totalSupply = 0;
    
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balance[from] = balance[from].sub(value);
        balance[to] = balance[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }
    
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function mint(address user, uint amount) internal {
        LP[user] = LP[user].add(amount);
        _totalSupply = _totalSupply.add(amount);
        emit Mint(user, amount);
    }
    /*
    _totalSupply = _totalSupply.add(amount);
    _balances[account] = _balances[account].add(amount);
    emit Transfer(address(0), account, amount);
    */
    function burn(address user, uint amount) internal {
        uint liquidity = LP[user];
        LP[user] = 0;//zero it out since we are withdrawing everything
        _totalSupply = _totalSupply.sub(liquidity);
        emit Burn(user, amount);
    }
    
    function balanceOf(address user) public view returns(uint amount) {
        amount = LP[user];
    }
    
    function totalSupply() public view returns(uint amount) {
        amount = _totalSupply;
    }
    
    /*====================================Pool================================*/
    
    function deposit(uint amount) public returns(bool) {
        IERC20(pBTC35aAddress).approve(stakingAddress, amount);
        IERC20(pBTC35aAddress).transferFrom(msg.sender, address(this), amount); //transfer pBTC35a to this contract
        Staking(stakingAddress).stake(amount);//stake the pBTC35a on mars
        pBTC35aStaked = pBTC35aStaked.add(amount);
        mint(msg.sender, getLPamount(amount));
        return true;
    }
    
    function withdrawl() public returns(bool) {
        unstake();//unstake all
        uint amount = getAmountLP(LP[msg.sender]);
        //uint marsAmount = getAmountMars(LP[msg.sender]);//uncomment to return users amount of mars
        burn(msg.sender, LP[msg.sender]);
        IERC20(pBTC35aAddress).transfer(msg.sender, amount);
        //IERC20(marsAddress).transfer(msg.sender, marsAmount);//uncomment to return users amount of mars
        restake();//restake the rest
    }
    
    function unstake() internal returns(bool) {
        //require(msg.sender == dev);
        Staking(stakingAddress).exit();
        return true;
    }
    
    function restake() internal returns(bool) {
        //require(msg.sender == dev);
        uint amount = IERC20(pBTC35aAddress).balanceOf(address(this));
        pBTC35aStaked = amount;
        if(amount != 0) {
            IERC20(pBTC35aAddress).approve(stakingAddress, amount);
            Staking(stakingAddress).stake(amount);
        }
    }
    
    function dumpIncome()internal returns(uint amount) {//dump wBTC earned to this contract
        //require(msg.sender == dev);
        Staking(stakingAddress).getIncome();//dump earned wBTC into contract
        amount = IERC20(pBTC35aAddress).balanceOf(address(this));
    }
    
    function swap(uint amountIn, uint amountOutMin, uint deadline) internal returns(uint amountOut) {//swap wBTC for pBTC35a on uniswap
        //require(msg.sender == dev);
        IERC20(wBTCAddress).approve(Unirouter, amountIn); //allow unirouter to send these tokens
        Uniswap(Unirouter).swapExactTokensForTokens(amountIn, amountOutMin, getPath(), address(this), deadline);
        amountOut = IERC20(pBTC35aAddress).balanceOf(address(this));
    }
    
    function getPath() internal view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = wBTCAddress;
        path[1] = pBTC35aAddress;
        return path;
    }
    
    function getAmountsOut(uint amountIn) internal view returns(uint amount) {//this needs fixing so it doesn't have to read a contract that may not have tokens at all
        amount = Uniswap(Unirouter).getAmountsOut(amountIn, getPath())[1];
    }
    
    function stake(uint amount) internal returns(bool) {//approve this shit..
        //require(msg.sender == dev);
        IERC20(pBTC35aAddress).approve(stakingAddress, amount);
        Staking(stakingAddress).stake(amount);//stake the newly aquired pBTC35a
        pBTC35aStaked = pBTC35aStaked + amount;
        return true;
    }

    function reinvest(uint _slippage, uint deadline) public returns(bool) {
        require(msg.sender == dev);
        require(Staking(stakingAddress).incomeEarned(address(this)) >= minBalance);//require earned wBTC is more than 0.1wBTC
        dumpIncome();
        uint thisBalance = IERC20(wBTCAddress).balanceOf(address(this));//get wBTC balance of contract
        uint poolFee = (thisBalance*25)/1000;//calculate pool fee of 2.5%
        uint amountIn = thisBalance-poolFee;//calculate amount of wBTC to spend on pBTC35a
        uint amountOut = getAmountsOut(amountIn);
        uint amountOutMin = (amountOut*_slippage)/100;
        uint pBTC35aAmount = swap(amountIn, amountOutMin, deadline);
        stake(pBTC35aAmount);//stake the newly aquired pBTC35a///
        pBTC35aStaked = pBTC35aStaked + pBTC35aAmount;//add new pBTC35a to the staked amount
        IERC20(wBTCAddress).transfer(dev, poolFee-100);//transfer 2.5% pool fee to owner
        //fees = fees+poolFee;
    }
    
    function getLPamount(uint amount) internal view returns(uint LPamount) {
        if(_totalSupply == 0) {
            LPamount = amount;
        } else {
            LPamount = (amount*pBTC35aStaked)/_totalSupply ;
        }
    }
    
    function getAmountLP(uint amount) internal view returns(uint tokenAmount) {
        tokenAmount = (amount*pBTC35aStaked) / _totalSupply ;
    }
    
    
    function getAmountMars(uint amount) internal view returns(uint tokenAmount) {
        uint totalMars = IERC20(marsAddress).balanceOf(address(this));
        tokenAmount = (amount*totalMars) / _totalSupply ;
    }
    
    function tokenBalanceOf(address account) public view returns(uint amount) {
        amount = getAmountLP(LP[account]);
    }

}
