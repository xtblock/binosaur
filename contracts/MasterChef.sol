// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import './math/SafeMath.sol';
import './token/BEP20/IBEP20.sol';
import './token/BEP20/SafeBEP20.sol';
import './access/Ownable.sol';


interface IMigratorChef {
  
    function migrate(IBEP20 token) external returns (IBEP20);
}

	  
  
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once XTT is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of XTTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accXttPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accXttPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. XTTs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that XTTs distribution occurs.
        uint256 accXttPerShare; // Accumulated XTTs per share, times 1e12. See below.
        uint256 executeTimestamp; // Timestamp to execute adding pool
        bool withUpdate;
        bool executed;
    }
    
    struct PoolAllocPointInfo {
        uint256 pid;       // Pool id
        uint256 allocPoint;  // How many allocation points assigned to this pool. XTTs to distribute per block.
        uint256 executeTimestamp; // Timestamp to execute adding pool
        bool withUpdate;
        bool executed;
    }

    // The XTT TOKEN!
    IBEP20 public xtt;  
  
    // XTT tokens created per block.
    uint256 public xttPerBlock;
    // Bonus muliplier for early xtt makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Store new value and execute when the time comes
    uint256 public NEW_BONUS_MULTIPLIER = 1;
    uint256 public NEW_BONUS_MULTIPLIER_TIMESTAMP = 0;
    
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;
    IMigratorChef public newMigrator;
    uint256 public newMigratorExecuteTimestamp = 0;
    

    // Info of each pool.
    PoolInfo[] public poolInfo;
    PoolInfo[] public waitingPoolInfo; // Pools are waiting to add
    PoolAllocPointInfo[] public poolAllocPointInfo; // Pools are waiting to update allocPoint
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when XTT mining starts.
    uint256 public startBlock;
    
    
    uint256 public constant MIN_TIME_LOCK_PERIOD = 24 hours; // 1 days
    

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetMigrator(address indexed user, IMigratorChef migrator);
    event UpdateMultiplier(address indexed user, uint256 multiplierNumber);

    constructor(
		// We will use XTT instead of CakeToken
        IBEP20 _xtt,
        /*
        Modified
		We do not need this token
        */
		// SyrupBar _syrup,
        /*
        End modified
        */
        uint256 _xttPerBlock,
        uint256 _startBlock
    ) public {
        xtt = _xtt;
        xttPerBlock = _xttPerBlock;
  
  
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _xtt,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accXttPerShare: 0,
            executeTimestamp: block.timestamp,
            withUpdate: false,
            executed: true
        }));

        totalAllocPoint = 1000;

    }

    function updateMultiplier(uint256 multiplierNumber, uint256 executeTimestamp) external onlyOwner {
        // Check the time
        require(
            executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        
        if(NEW_BONUS_MULTIPLIER_TIMESTAMP > 0 && block.timestamp >= NEW_BONUS_MULTIPLIER_TIMESTAMP){
            if(BONUS_MULTIPLIER != NEW_BONUS_MULTIPLIER){
                BONUS_MULTIPLIER = NEW_BONUS_MULTIPLIER;
            }
        }
        
        NEW_BONUS_MULTIPLIER = multiplierNumber;
        NEW_BONUS_MULTIPLIER_TIMESTAMP = executeTimestamp;
        
        emit UpdateMultiplier(msg.sender, multiplierNumber);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate, uint256 _executeTimestamp) external onlyOwner {
        require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        waitingPoolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: 0,
            accXttPerShare: 0,
            executeTimestamp: _executeTimestamp,
            withUpdate: _withUpdate,
            executed: false
        }));
        
    }
    
    // Add a new lp to the pool. Can only be called by the owner.
    function executeAddPools() external onlyOwner {
        uint256 length = waitingPoolInfo.length;
        if(length > 0){
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = waitingPoolInfo[pid];
                if(!pool.executed && pool.executeTimestamp <= block.timestamp){
                
                    if (pool.withUpdate) {
                        massUpdatePools();
                    }
                    uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
                    totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
                    poolInfo.push(PoolInfo({
                        lpToken: pool.lpToken,
                        allocPoint: pool.allocPoint,
                        lastRewardBlock: lastRewardBlock,
                        accXttPerShare: 0,
                        executeTimestamp: pool.executeTimestamp,
                        withUpdate: pool.withUpdate,
                        executed: true
                    }));
                    pool.executed = true;
                    updateStakingPool();
                    
                    // Remove this item
                    removeWaitingPool(pid);
                    pid--;
                    length--;   
                }
                
            }    
        }
        
    }

    function removeWaitingPool(uint index)  internal onlyOwner {
        if (index >= waitingPoolInfo.length) return;

        for (uint i = index; i<waitingPoolInfo.length-1; i++){
            waitingPoolInfo[i] = waitingPoolInfo[i+1];
        }
        waitingPoolInfo.pop();
        //delete waitingPoolInfo[waitingPoolInfo.length-1];
    }



    // Update the given pool's XTT allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate, uint256 _executeTimestamp) external onlyOwner {
         require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        
        poolAllocPointInfo.push(PoolAllocPointInfo({
            pid: _pid,
            allocPoint: _allocPoint,
            executeTimestamp: _executeTimestamp,
            withUpdate: _withUpdate,
            executed: false
        }));
    }
    
    // Update the given pool's XTT allocation point. Can only be called by the owner.
    function executeUpdateAllocPoint() external onlyOwner {
        
        uint256 length = poolAllocPointInfo.length;
        if(length > 0){
            for (uint256 index = 0; index < length; ++index) {
                PoolAllocPointInfo storage poolAllocPoint = poolAllocPointInfo[index];
                if(!poolAllocPoint.executed && poolAllocPoint.executeTimestamp <= block.timestamp){
                    if (poolAllocPoint.withUpdate) {
                        massUpdatePools();
                    }else{
                        updatePool(poolAllocPoint.pid);
                    }
            	  
                    uint256 prevAllocPoint = poolInfo[poolAllocPoint.pid].allocPoint;
                    if (prevAllocPoint != poolAllocPoint.allocPoint) {
                        poolInfo[poolAllocPoint.pid].allocPoint = poolAllocPoint.allocPoint;
                        totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(poolAllocPoint.allocPoint);
                        updateStakingPool();
                    }
                    
                    poolAllocPoint.executed = true;
                    
                    
                    // Remove this item
                    
                    removeAllocPoint(index);
                    index--;
                    length--;
                }
                
            }
        }
        
    }
    
    function removeAllocPoint(uint index)  internal onlyOwner {
        if (index >= poolAllocPointInfo.length) return;

        for (uint i = index; i<poolAllocPointInfo.length-1; i++){
            poolAllocPointInfo[i] = poolAllocPointInfo[i+1];
        }
        poolAllocPointInfo.pop();
        //delete poolAllocPointInfo[poolAllocPointInfo.length-1];
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator, uint256 _executeTimestamp) external onlyOwner {
        require(
            _executeTimestamp >= block.timestamp.add(MIN_TIME_LOCK_PERIOD),
            "_executeTimestamp cannot be sooner than MIN_TIME_LOCK_PERIOD"
        );
        
        newMigrator = _migrator;
        newMigratorExecuteTimestamp = _executeTimestamp;
        
        emit SetMigrator(msg.sender, _migrator);
    }
    
    // Execute Set the migrator contract. Can only be called by the owner.
    function executeSetMigrator() external onlyOwner {
        if(newMigratorExecuteTimestamp > 0 && newMigratorExecuteTimestamp <= block.timestamp){
            migrator = newMigrator;
            newMigratorExecuteTimestamp = 0;
            emit SetMigrator(msg.sender, newMigrator);
        }
    }


    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) external {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        // Check to update new value
        if(NEW_BONUS_MULTIPLIER_TIMESTAMP > 0 && block.timestamp >= NEW_BONUS_MULTIPLIER_TIMESTAMP){
            return _to.sub(_from).mul(NEW_BONUS_MULTIPLIER);
        }
        
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending XTTs on frontend.
    function pendingCake(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accXttPerShare = pool.accXttPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(xttPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accXttPerShare = accXttPerShare.add(cakeReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accXttPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
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
        uint256 xttReward = multiplier.mul(xttPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        /*
        Modified
        Do not need to mint more tokens
        */
        // cake.mint(devaddr, cakeReward.div(10));
        // cake.mint(address(syrup), cakeReward);
        /*
        End modified
        */	
  
        pool.accXttPerShare = pool.accXttPerShare.add(xttReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for XTT allocation.
    function deposit(uint256 _pid, uint256 _amount) external {

        require (_pid != 0, 'deposit XTT by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accXttPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeXttTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXttPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {

        require (_pid != 0, 'withdraw XTT by unstaking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accXttPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeXttTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXttPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake XTT tokens to MasterChef
    function enterStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accXttPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeXttTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXttPerShare).div(1e12);
        /*
        Modified
		Do not need to mint this token
        */
        // syrup.mint(msg.sender, _amount);
        /*
        End modified
        */

        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw XTT tokens from STAKING.
    function leaveStaking(uint256 _amount) external {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accXttPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeXttTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accXttPerShare).div(1e12);
        /*
        Modified
		Do not need to burn this token
        */
        // syrup.burn(msg.sender, _amount);
        /*
        End modified
        */
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe xtt transfer function, just in case if rounding error causes pool to not have enough XTTs.
    function safeXttTransfer(address _to, uint256 _amount) internal {
        xtt.safeTransfer(_to, _amount);
    }
}
