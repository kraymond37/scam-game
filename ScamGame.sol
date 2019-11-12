pragma solidity ^0.5.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
	// Empty internal constructor, to prevent people from mistakenly deploying
	// an instance of this contract, which should be used via inheritance.
	constructor() internal {}
	// solhint-disable-previous-line no-empty-blocks

	function _msgSender() internal view returns (address) {
		return msg.sender;
	}
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
	address private _owner;

	/**
	 * @dev Initializes the contract setting the deployer as the initial owner.
	 */
	constructor () internal {
		_owner = _msgSender();
	}

	/**
	 * @dev Throws if called by any account other than the owner.
	 */
	modifier onlyOwner() {
		require(isOwner(), "Ownable: caller is not the owner");
		_;
	}

	/**
	 * @dev Returns true if the caller is the current owner.
	 */
	function isOwner() public view returns (bool) {
		return _msgSender() == _owner;
	}

	/**
	 * @dev Transfers ownership of the contract to a new account (`newOwner`).
	 * Can only be called by the current owner.
	 */
	function transferOwnership(address newOwner) public onlyOwner {
		require(newOwner != address(0), "Ownable: new owner is the zero address");
		_owner = newOwner;
	}
}

/**
 * @title Roles
 * @dev Library for managing addresses assigned to a Role.
 */
library Roles {
	struct Role {
		mapping(address => bool) bearer;
	}

	/**
	 * @dev Give an account access to this role.
	 */
	function add(Role storage role, address account) internal {
		require(!has(role, account), "Roles: account already has role");
		role.bearer[account] = true;
	}

	/**
	 * @dev Remove an account's access to this role.
	 */
	function remove(Role storage role, address account) internal {
		require(has(role, account), "Roles: account does not have role");
		role.bearer[account] = false;
	}

	/**
	 * @dev Check if an account has this role.
	 * @return bool
	 */
	function has(Role storage role, address account) internal view returns (bool) {
		require(account != address(0), "Roles: account is the zero address");
		return role.bearer[account];
	}
}

/**
 * @title WhitelistAdminRole
 * @dev WhitelistAdmins are responsible for assigning and removing Whitelisted accounts.
 */
contract WhitelistAdminRole is Context, Ownable {
	using Roles for Roles.Role;

	Roles.Role private _whitelistAdmins;

	constructor () internal {
	}

	modifier onlyWhitelistAdmin {
		require(isWhitelistAdmin(_msgSender()) || isOwner(), "WhitelistAdminRole: caller does not have the WhitelistAdmin role");
		_;
	}

	function isWhitelistAdmin(address account) public view returns (bool) {
		return _whitelistAdmins.has(account) || isOwner();
	}

	function addWhitelistAdmin(address account) public onlyOwner {
		_whitelistAdmins.add(account);
	}

	function removeWhitelistAdmin(address account) public onlyOwner {
		_whitelistAdmins.remove(account);
	}
}

contract ScamGame is WhitelistAdminRole {
    using SafeMath for *;

	struct User {
		address userAddress;
		bytes6 inviteCode;
		bytes6 inviter;
		mapping(uint => address[]) memberList;
		uint memberCount;
	}

    struct UserInvest {
        address userAddress;
        uint freeAmount;
        uint freezeAmount;
        uint startTime;
        uint endTime;
        uint staticBonus;
        uint shareBonus;
        uint levelReward;
		uint investTotal;
		uint investCount;
		uint validMemberCount;
		uint level;
		uint withdrawTotal;
    }

    uint ethWei = 1 ether;
	uint minInvest = 0.5 ether;
	uint maxInvest = 60 ether;
    uint period = 10 minutes;
    uint memberDepthLimit = 15;
    uint upgradeDepthLimit = 10;
    uint maxDepth = 1024;
	uint freeScale = 20;
	uint staticScale = 8;
	uint maxLevel = 4;
    uint equalLevelRewardScale = 10;
    uint[] levelRewardScale = [0, 5, 6, 8, 10];
	mapping(address => User) userList;
    mapping(bytes6 => address) addressList;
	mapping(address => UserInvest) userInvestList;
	uint investTotal;
	uint investCount;

    modifier isHuman {
		address addr = msg.sender;
		uint codeLength;
		assembly {codeLength := extcodesize(addr)}
		require(codeLength == 0, "sorry humans only");
		require(tx.origin == msg.sender, "sorry, humans only");
		_;
	}

	constructor () public {
		address rootAddress = 0x478513c83aadCeFBABE3D74B8B8c22F46bc3D395;
		bytes6 rootCode = 0x303030303030;
		userList[rootAddress].userAddress = rootAddress;
		userList[rootAddress].inviteCode = rootCode;
		addressList[rootCode] = rootAddress;
	}

	function() external payable {
	}

	function getStatus() public view returns(uint total, uint count) {
		return (investTotal, investCount);
	}

	function getUser(address addr) public view returns (uint[12] memory info, bytes6 inviter, bytes6 inviteCode) {
//		require(isWhitelistAdmin(msg.sender) || msg.sender == addr, "you are not allowed to view user privacy");
		User memory user = userList[addr];
		UserInvest memory userInvest = userInvestList[addr];

		info[0] = userInvest.level;
		info[1] = user.memberCount;
		info[2] = userInvest.validMemberCount;
		info[3] = userInvest.investTotal;
		info[4] = userInvest.investCount;
		info[5] = userInvest.freezeAmount;
		info[6] = userInvest.freeAmount;
		info[7] = userInvest.staticBonus;
		info[8] = userInvest.shareBonus;
		info[9] = userInvest.levelReward;
		info[10] = userInvest.startTime;
		info[11] = userInvest.endTime;

		inviter = user.inviter;
		inviteCode = user.inviteCode;

		return (info, inviter, inviteCode);
	}

	function register(bytes6 inviter, bytes6 inviteCode) external isHuman {
		require(userList[msg.sender].userAddress == address(0x0), "user has registered already");
		require(addressList[inviter] != address(0x0), "inviter not exist");
		require(addressList[inviteCode] == address(0x0), "invite code is occupied");

		userList[msg.sender].userAddress = msg.sender;
		userList[msg.sender].inviteCode = inviteCode;
		userList[msg.sender].inviter = inviter;
		addressList[inviteCode] = msg.sender;

		address parent = addressList[inviter];
		for (uint i = 0; i < memberDepthLimit; i++) {
			userList[parent].memberList[i].push(msg.sender);
			userList[parent].memberCount ++;

			if (userList[parent].inviter == bytes6(0x0)) {
				break;
			}
		}
	}

	function invest() external isHuman payable {
		require(userList[msg.sender].userAddress != address(0x0), "user not register");

		UserInvest storage userInvest = userInvestList[msg.sender];

		// 第一次投注
		if (userInvest.userAddress == address(0x0)) {
			require(msg.value >= 1 * ethWei && msg.value <= 20 * ethWei, "between 1 and 20");

			userInvest.userAddress = msg.sender;
			userInvest.freezeAmount = msg.value;
			userInvest.startTime = now;
			userInvest.endTime = now + period;
			userInvest.investTotal = msg.value;
			userInvest.investCount = 1;
			addParentValidMembers(msg.sender);
			investTotal.add(msg.value);
			investCount++;
		}
		// 非第一次投注
		else {
			require(userInvest.startTime == 0, "this period is unfinished or to be settle");

			uint lastFreeAmount = userInvest.freezeAmount.div(100 - freeScale).mul(freeScale);
			uint minLimit = minInvest > lastFreeAmount.mul(70).div(100) ? minInvest : lastFreeAmount.mul(70).div(100);
			uint lastInvest = userInvest.freezeAmount.div(100 - freeScale).mul(100);
			uint maxLimit = maxInvest < lastInvest + 5 * ethWei ? maxInvest : lastInvest + 5 * ethWei;
			maxLimit = maxLimit.sub(userInvest.freezeAmount);
			require(msg.value >= minLimit && msg.value <= maxLimit, "between xxx and xxx");

			userInvest.freezeAmount = userInvest.freezeAmount.add(msg.value);
			userInvest.startTime = now;
			userInvest.endTime = now + period;
			userInvest.investTotal = userInvest.investTotal.add(msg.value);
			userInvest.investCount ++;
			investTotal.add(msg.value);
			investCount++;
		}
	}

	function settlement() external isHuman {
		UserInvest storage userInvest = userInvestList[msg.sender];
		require(userInvest.endTime <= now, "not time to settle");
		require(userInvest.endTime != 0, "no invest or settled already");

		userInvest.staticBonus= userInvest.staticBonus.add(userInvest.freezeAmount.mul(staticScale).div(100));
		calcReward(msg.sender);

		uint sendValue = userInvest.freezeAmount.mul(freeScale).div(100);
		userInvest.freezeAmount = userInvest.freezeAmount.mul(100 - freeScale).div(100);
		userInvest.startTime = 0;
		userInvest.endTime = 0;

		address payable userAddress = msg.sender;
		sendValue = sendValue.min(address(this).balance);
		userAddress.transfer(sendValue);
	}

	function withdraw() external isHuman {
		UserInvest storage userInvest = userInvestList[msg.sender];
		uint sendValue = userInvest.staticBonus.add(userInvest.shareBonus).add(userInvest.levelReward);
		require(sendValue > 0, "you profit is 0");

		userInvest.staticBonus = 0;
		userInvest.shareBonus = 0;
		userInvest.levelReward = 0;

		address payable userAddress = msg.sender;
		sendValue = sendValue.min(address(this).balance);
		userInvest.withdrawTotal = userInvest.withdrawTotal.add(sendValue);
		userAddress.transfer(sendValue);
	}

	function upgrade(address addr) external onlyWhitelistAdmin {
		require(userInvestList[addr].level < maxLevel, "already the top level");

		uint valid_count;
		address[] memory invitees = userList[addr].memberList[0];

		// Level_0 → Level_1
		if (userInvestList[addr].level == 0) {
			require(userInvestList[addr].investTotal >= 10, "invest < 10eth");
			require(userInvestList[addr].validMemberCount >= 100, "valid members < 100");

			for (uint i = 0; i < invitees.length; i++) {
				if (userInvestList[addr].userAddress != address(0x0)) {
					valid_count++;
				}
				if (valid_count >= 10) {
					break;
				}
			}
			require(valid_count >= 10, "valid invitees < 10");

			userInvestList[addr].level ++;
		}
		// Level_n → Level_(n+1)
		else {
			for (uint i = 0; i < invitees.length; i++) {
				if (userInvestList[invitees[i]].level >= userInvestList[addr].level) {
					valid_count++;
					if (valid_count >= 3) {
						break;
					}
				} else {
					for (uint depth = 0; depth < upgradeDepthLimit - 1; depth++) {
						address[] memory members = userList[invitees[i]].memberList[depth];
						for (uint j = 0; j < members.length; j++) {
							if (userInvestList[members[j]].level >= userInvestList[addr].level) {
								valid_count++;
								break;
							}
						}
						if (valid_count >= 3) {
							break;
						}
					}
					if (valid_count >= 3) {
						break;
					}
				}
			}

			require(valid_count >= 3, "valid communities < 3");
			userInvestList[addr].level ++;
		}
	}

	function addParentValidMembers(address sender) private {
		if (userList[sender].inviter == bytes6(0x0)) {
			return;
		}
		address parent = addressList[userList[sender].inviter];
		for (uint i = 0; i < memberDepthLimit; i++) {
			userInvestList[parent].validMemberCount ++;
			if (userList[parent].inviter == bytes6(0x0)) {
				break;
			}
			parent = addressList[userList[parent].inviter];
		}
	}

	function calcReward(address sender) private {
		UserInvest memory userInvest = userInvestList[sender];
		uint selfProfit = userInvest.staticBonus + userInvest.shareBonus + userInvest.levelReward;
		if (selfProfit == 0) {
			return;
		}

		if (userList[sender].inviter == bytes6(0x0)) {
			return;
		}

		uint shareScale;
		uint baseAmount;
		uint currentLevel = userInvest.level;
		bool shouldStop = false;
		address nearestEqualLevelAddress;
		address parent = addressList[userList[sender].inviter];
		for (uint depth = 0; depth < maxDepth; depth++) {
			// 只有参与中的用户才有奖励
			bool hasReward = userInvestList[parent].startTime != 0 && userInvestList[parent].endTime > now;

			// 分享收益限15代以内
			if (depth < memberDepthLimit && hasReward) {
				if (depth == 0) {
					shareScale = 15;
				} else if (depth == 1) {
					shareScale = 10;
				} else if (depth == 2) {
					shareScale = 5;
				} else if (depth >= 3 && depth <= 9) {
					shareScale = 3;
				} else if (depth >= 10 && depth <= 14) {
					shareScale = 1;
				}
				baseAmount = userInvest.freezeAmount.min(userInvestList[parent].freezeAmount);
				userInvestList[parent].shareBonus = userInvestList[parent].shareBonus.add(baseAmount.mul(staticScale).div(100).mul(shareScale).div(100));
			}

			// 节点奖励限初级节点以上, 1024代
			if (!shouldStop && userInvestList[parent].level >= 1) {
				uint levelScale = 0;
				if (userInvestList[parent].level > currentLevel) {
					// 当前节点的级别最大时正常获得奖励
					levelScale = levelRewardScale[userInvestList[parent].level];
					currentLevel = userInvestList[parent].level;
				} else if (userInvestList[parent].level == currentLevel) {
					// 平级节点, 中级节点以上才有奖励, 只可能有一个, 那就是第一个与sender相同等级的节点
					if (currentLevel > 1 && nearestEqualLevelAddress == address(0x0) && userInvest.level == currentLevel) {
						nearestEqualLevelAddress = parent;
						levelScale = equalLevelRewardScale;
					}
				} else {
					// 被越级了没奖励
				}

				if (hasReward && levelScale != 0) {
					userInvestList[parent].levelReward = userInvestList[parent].levelReward.add(selfProfit.mul(levelScale));
				}

				// 如果已到最大等级, 除了平级节点不可能再有别的奖励
				if (currentLevel == 4) {
					// 如果已经找到平级节点或者不可能存在平级节点, 就可以停止了
					if (nearestEqualLevelAddress != address(0x0) || userInvest.level != 4) {
						shouldStop = true;
					}
				}
			}

			// 此时上级节点的分享收益和节点奖励都到头了
			if (depth >= memberDepthLimit && shouldStop) {
				break;
			}

			if (userList[parent].inviter == bytes6(0x0)) {
				break;
			}
			parent = addressList[userList[parent].inviter];
		}
	}
}

/**
* @title SafeMath
* @dev Math operations with safety checks that revert on error
*/
library SafeMath {
	/**
	* @dev Multiplies two numbers, reverts on overflow.
	*/
	function mul(uint256 a, uint256 b) internal pure returns (uint256) {
		// Gas optimization: this is cheaper than requiring 'a' not being zero, but the
		// benefit is lost if 'b' is also tested.
		// See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
		if (a == 0) {
			return 0;
		}

		uint256 c = a * b;
		require(c / a == b, "mul overflow");

		return c;
	}

	/**
	* @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
	*/
	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b > 0, "div zero");
		// Solidity only automatically asserts when dividing by 0
		uint256 c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold

		return c;
	}

	/**
	* @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
	*/
	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b <= a, "lower sub bigger");
		uint256 c = a - b;

		return c;
	}

	/**
	* @dev Adds two numbers, reverts on overflow.
	*/
	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		require(c >= a, "overflow");

		return c;
	}

	/**
	* @dev Divides two numbers and returns the remainder (unsigned integer modulo),
	* reverts when dividing by zero.
	*/
	function mod(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b != 0, "mod zero");
		return a % b;
	}

	/**
	* @dev compare two numbers and returns the smaller one.
	*/
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a > b ? b : a;
	}
}