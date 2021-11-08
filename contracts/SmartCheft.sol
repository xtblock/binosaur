// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./math/SafeMath.sol";
import "./token/BEP20/IBEP20.sol";
import "./token/BEP20/SafeBEP20.sol";
import "./access/Ownable.sol";

contract SmartChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardBUSD; // reward in BUSD
        uint256 rewardDebtBUSD; // reward debt in BUSD
        uint256 rewardUSDT; // reward in USDT
        uint256 rewardDebtUSDT; // reward debt in USDT
        uint256 rewardUSDC; // reward debt in USDC
        uint256 rewardDebtUSDC; // reward in USDC
        uint256 rewardDAI; // reward in DAI
        uint256 rewardDebtDAI; // reward debt in DAI
        uint256 rewardDebtXTT; // reward debt in XTT-b20
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. XTTs to distribute per block.
        uint256 lastRewardBlock; // Last block number that XTTs distribution occurs.
        uint256 accXttPerShare; // Accumulated XTTs per share, times 1e12. See below.
    }
    
    // Smart Chain
    IBEP20 public tokenBUSD = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IBEP20 public tokenUSDT = IBEP20(0x55d398326f99059fF775485246999027B3197955);
    IBEP20 public tokenUSDC = IBEP20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
    IBEP20 public tokenDAI = IBEP20(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3);
   

    // The XTT TOKEN!
    IBEP20 public syrup;
    IBEP20 public rewardToken;

    // XTT tokens created per block.
    uint256 public rewardPerBlock;
    uint256 public newRewardPerBlock;
    uint256 public newRewardPerBlockTimestamp = 0;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    mapping(address => bool) userExists;
    address [] public userList;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 private totalAllocPoint = 0;
    // The block number when XTT mining starts.
    uint256 public startBlock;
    uint256 public newStartBlock;
    uint256 public newStartBlockTimestamp;
    // The block number when XTT mining ends.
    uint256 public bonusEndBlock;
    uint256 public newBonusEndBlock;
    uint256 public newBonusEndBlockTimestamp;
    // Min desposit amount
    uint256 public minDepositAmount;
    uint256 public newMinDepositAmount;
    uint256 public newMinDepositAmountTimestamp;

    uint256 public constant MIN_TIME_LOCK_PERIOD = 24 hours; // 1 days

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event NewStartAndEndBlocks(
        address indexed user,
        uint256 startBlock,
        uint256 endBlock
    );
    event NewStartBlock(address indexed user, uint256 startBlock);
    event NewEndBlock(address indexed user, uint256 endBlock);
    event NewRewardPerBlock(address indexed user, uint256 rewardPerBlock);
    event NewMinDepositAmount(address indexed user, uint256 minDepositAmount);
    event NewRewardDistribution(address indexed user, uint256 amount, string tokenSymbol);

    constructor(
        IBEP20 _syrup,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _minDepositAmount
    ) public {
        syrup = _syrup;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        minDepositAmount = _minDepositAmount;

        // staking pool
        poolInfo.push(
            PoolInfo({
                lpToken: _syrup,
                allocPoint: 1000,
                lastRewardBlock: startBlock,
                accXttPerShare: 0
            })
        );

        totalAllocPoint = 1000;
    }

    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }

    function updateRewardPerBlock(
        uint256 _rewardPerBlock,
        uint256 _executeTimestamp
    ) external onlyOwner {
        require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        newRewardPerBlock = _rewardPerBlock;
        newRewardPerBlockTimestamp = _executeTimestamp;

        emit NewRewardPerBlock(msg.sender, _rewardPerBlock);
    }

    function executeUpdateRewardPerBlock() external onlyOwner {
        if (
            newRewardPerBlockTimestamp > 0 &&
            newRewardPerBlockTimestamp <= block.timestamp
        ) {
            rewardPerBlock = newRewardPerBlock;
            newRewardPerBlockTimestamp = 0;
            updatePool(0);
            emit NewRewardPerBlock(msg.sender, rewardPerBlock);
        }
    }


    function updateStartBlock(uint256 _startBlock, uint256 _executeTimestamp)
        external
        onlyOwner
    {
        require(block.number < startBlock, "Pool has started");
        require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        require(
            _startBlock < bonusEndBlock,
            "New startBlock must be lower than endBlock"
        );
        require(
            block.number < _startBlock,
            "New startBlock must be higher than current block"
        );

        newStartBlock = _startBlock;
        newStartBlockTimestamp = _executeTimestamp;

        emit NewStartBlock(msg.sender, _startBlock);
    }

    function executeUpdateStartBlock() external onlyOwner {
        require(block.number < startBlock, "Pool has started");

        require(
            newStartBlock < bonusEndBlock,
            "New startBlock must be lower than endBlock"
        );
        require(
            block.number < newStartBlock,
            "New startBlock must be higher than current block"
        );

        if (
            newStartBlockTimestamp > 0 &&
            newStartBlockTimestamp <= block.timestamp
        ) {
            PoolInfo storage pool = poolInfo[0];

            startBlock = newStartBlock;
            newStartBlockTimestamp = 0;

            // Set the lastRewardBlock as the startBlock
            pool.lastRewardBlock = startBlock;

            emit NewStartBlock(msg.sender, startBlock);
        }
    }

    function updateEndBlock(uint256 _bonusEndBlock, uint256 _executeTimestamp)
        external
        onlyOwner
    {
        require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        require(
            startBlock < _bonusEndBlock,
            "New endBlock must be higher than startBlock"
        );

        require(
            block.number <= _bonusEndBlock,
            "New endBlock must be higher than current block"
        );

        newBonusEndBlock = _bonusEndBlock;
        newBonusEndBlockTimestamp = _executeTimestamp;

        emit NewEndBlock(msg.sender, _bonusEndBlock);
    }

    function executeUpdateEndBlock() external onlyOwner {
        require(
            startBlock < newBonusEndBlock,
            "New endBlock must be higher than startBlock"
        );
        require(
            block.number < newBonusEndBlock,
            "New endBlock must be higher than current block"
        );
        if (
            newBonusEndBlockTimestamp > 0 &&
            newBonusEndBlockTimestamp <= block.timestamp
        ) {
            bonusEndBlock = newBonusEndBlock;
            newBonusEndBlockTimestamp = 0;

            emit NewEndBlock(msg.sender, bonusEndBlock);
        }
    }

    function updateMinDepositAmount(
        uint256 _minDepositAmount,
        uint256 _executeTimestamp
    ) external onlyOwner {
        require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );

        newMinDepositAmount = _minDepositAmount;
        newMinDepositAmountTimestamp = _executeTimestamp;

        emit NewMinDepositAmount(msg.sender, _minDepositAmount);
    }

    function executeUpdateMinDepositAmount() external onlyOwner {
        if (
            newMinDepositAmountTimestamp > 0 &&
            newMinDepositAmountTimestamp <= block.timestamp
        ) {
            minDepositAmount = newMinDepositAmount;
            newMinDepositAmountTimestamp = 0;

            emit NewMinDepositAmount(msg.sender, minDepositAmount);
        }
    }

    // Return min deposit amount.
    function getMinDepositAmount() public view returns (uint256) {
        if (
            newMinDepositAmountTimestamp > 0 &&
            block.timestamp >= newMinDepositAmountTimestamp
        ) {
            return newMinDepositAmount;
        }

        return minDepositAmount;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accXttPerShare = pool.accXttPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        
        // if staked amount is less than minDepositAmount
        if(user.amount < getMinDepositAmount()){
            return 0;
        }
        
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint256 xttReward = multiplier
                .mul(rewardPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accXttPerShare = accXttPerShare.add(
                xttReward.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accXttPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 xttReward = multiplier
            .mul(rewardPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);
        pool.accXttPerShare = pool.accXttPerShare.add(
            xttReward.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() external {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Stake SYRUP tokens to SmartChef
    function deposit(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        updatePool(0);
        if (user.amount > 0 && (user.amount >= getMinDepositAmount() || (user.amount + _amount >= getMinDepositAmount()))) {
            uint256 pending = user
                .amount
                .mul(pool.accXttPerShare)
                .div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        if (_amount > 0) {
            require(
                user.amount + _amount >= getMinDepositAmount(),
                "Deposit amount must be greater than minDepositAmount"
            );
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
            if(!userExists[msg.sender]){
                //userList.push(msg.sender) -1;
                userList.push(msg.sender);
                userExists[msg.sender] = true;
            }
        }
        user.rewardDebt = user.amount.mul(pool.accXttPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    // Withdraw SYRUP tokens from STAKING.
    function withdraw(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accXttPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0 && user.amount >= getMinDepositAmount()) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if (_amount > 0) {
            /*
            require(
                ((user.amount == _amount) || (user.amount - _amount >= getMinDepositAmount())),
                "You can withdraw all or your remain stake amount must be greater than minDepositAmount"
            );
            */
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            
        }
        user.rewardDebt = user.amount.mul(pool.accXttPerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }
    
    function getTotalSupply() internal view returns (uint256) {
        //PoolInfo storage pool = poolInfo[0];
        //return pool.lpToken.balanceOf(address(this));
        uint256 totalSupply = 0;
        uint256 length = userList.length;
        for (uint256 id = 0; id < length; ++id) {
            UserInfo storage user = userInfo[userList[id]];
            if(user.amount >= getMinDepositAmount()){
                totalSupply = totalSupply.add(user.amount);
            }
        }
        
        return totalSupply;
    }
    
    //Distribute rewards
    function rewardDistribution(uint256 _amount, string memory _tokenSymbol) external onlyOwner{
        
        if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("BUSD"))){
            require(tokenBUSD.balanceOf(address(this)) >= _amount, "Not enough BUSD");
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDT"))){
            require(tokenUSDT.balanceOf(address(this)) >= _amount, "Not enough USDT");
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDC"))){
            require(tokenUSDC.balanceOf(address(this)) >= _amount, "Not enough USDC");
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("DAI"))){
            require(tokenDAI.balanceOf(address(this)) >= _amount, "Not enough DAI");
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("XTT-b20"))){
            require(_amount > 0, "_amount must be greater than 0");
        }
        
        
        uint256 totalSupply = getTotalSupply();
        uint256 length = userList.length;
        for (uint256 id = 0; id < length; ++id) {
            UserInfo storage user = userInfo[userList[id]];
            if(user.amount >= getMinDepositAmount()){
                uint256 pendingRewards = user.amount.mul(1e12).div(totalSupply).mul(_amount).div(1e12);
                if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("BUSD"))){
                    user.rewardBUSD = user.rewardBUSD.add(pendingRewards);
                }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDT"))){
                    user.rewardUSDT = user.rewardUSDT.add(pendingRewards);
                }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDC"))){
                    user.rewardUSDC = user.rewardUSDC.add(pendingRewards);
                }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("DAI"))){
                    user.rewardDAI = user.rewardDAI.add(pendingRewards);
                }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("XTT-b20"))){
                    user.amount = user.amount.add(pendingRewards);
                    user.rewardDebtXTT = user.rewardDebtXTT.add(pendingRewards);
                }
            }
        }   
        
        NewRewardDistribution(msg.sender, _amount, _tokenSymbol);
    }
    
    function withdrawReward(string memory _tokenSymbol) external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = 0;
        if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("BUSD"))){
            require(user.rewardBUSD > 0, "withdraw: not good");
            tokenBUSD.safeTransfer(address(msg.sender), user.rewardBUSD);
            user.rewardDebtBUSD = user.rewardDebtBUSD.add(user.rewardBUSD);
            amount = user.rewardBUSD;
            user.rewardBUSD = 0;
            emit Withdraw(msg.sender, amount);  
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDT"))){
            require(user.rewardUSDT > 0, "withdraw: not good");
            tokenUSDT.safeTransfer(address(msg.sender), user.rewardUSDT);
            user.rewardDebtUSDT = user.rewardDebtUSDT.add(user.rewardUSDT);
            amount = user.rewardUSDT;
            user.rewardUSDT = 0;
            emit Withdraw(msg.sender, amount);
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("USDC"))){
            require(user.rewardUSDC > 0, "withdraw: not good");
            tokenUSDC.safeTransfer(address(msg.sender), user.rewardUSDC);
            user.rewardDebtUSDC = user.rewardDebtUSDC.add(user.rewardUSDC);
            amount = user.rewardUSDC;
            user.rewardUSDC = 0;
            emit Withdraw(msg.sender, amount);
        }else if(keccak256(abi.encodePacked(_tokenSymbol)) == keccak256(abi.encodePacked("DAI"))){
            require(user.rewardDAI > 0, "withdraw: not good");
            tokenDAI.safeTransfer(address(msg.sender), user.rewardDAI);
            user.rewardDebtDAI = user.rewardDebtDAI.add(user.rewardDAI);
            amount = user.rewardDAI;
            user.rewardDAI = 0;
            emit Withdraw(msg.sender, amount);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(
            _amount < rewardToken.balanceOf(address(this)),
            "not enough token"
        );
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }
}
