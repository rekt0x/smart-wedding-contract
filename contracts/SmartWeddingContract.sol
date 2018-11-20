pragma solidity 0.4.24;


/**
 * @title SmartWeddingContract
 * @dev The contract has both addresses of the husband and the wife. It is capable of handling assets, funds and
 * dissolution. A multisig variant is used to consider the decision of both parties.
 */
contract SmartWeddingContract {
	event WrittenContractProposed(string ipfsHash, address wallet);
	event Signed(address wallet);
	event ContractSigned();
	event AssetProposed(string asset, address wallet);
	event AssetAddApproved(string asset, address wallet);
	event AssetAdded(string asset);
	event AssetRemoveApproved(string asset, address wallet);
	event AssetRemoved(string asset);
	event DivorceApproved(address wallet);
	event Divorced();
	event Sent(address wallet, uint amount);
	event Received(address wallet, uint amount);

	bool public signed = false;
	bool public divorced = false;

	mapping (address => bool) hasSigned;
	mapping (address => bool) hasDivorced;

	address public husbandAddress;
	address public wifeAddress;
	string public writtenContractIpfsHash;

	struct Asset {
		string data;
		uint husbandAllocation;
		uint wifeAllocation;
		bool added;
		bool removed;
		mapping (address => bool) hasApprovedAdd;
		mapping (address => bool) hasApprovedRemove;
	}

	Asset[] public assets;

	/**
	 * @dev Modifier that only allows spouse execution.
 	 */
	modifier onlySpouse() {
		require(msg.sender == husbandAddress || msg.sender == wifeAddress, "Sender is not a spouse");
		_;
	}

	/**
	 * @dev Modifier that checks if the contract has been signed by both spouses.
 	 */
	modifier isSigned() {
		require(signed == true, "Contract is not signed by both spouses yet");
		_;
	}

	/**
	 * @dev Modifier that only allows execution if the spouses have not been divorced.
 	 */
	modifier isNotDivorced() {
		require(divorced == false, "Can not be called after dissolution");
		_;
	}

	/**
	 * @dev Internal helper function to check if a string is the same as another.
	 */
	function isSameString(string string1, string string2) internal pure returns (bool) {
		return keccak256(abi.encodePacked(string1)) != keccak256(abi.encodePacked(string2));
	}

	/**
	 * @dev Constructor sets the addresses of both spouses.
	 * @param _husbandAddress Wallet address of the husband.
	 * @param _wifeAddress Wallet address of the wife.
	 */
	constructor(address _husbandAddress, address _wifeAddress) public {
		require(_husbandAddress != address(0), "Husbands address must not be address zero");
		require(_wifeAddress != address(0), "Wife address must not be address zero");
		require(_husbandAddress != _wifeAddress, "Husband address must not equal wife address");

		husbandAddress = _husbandAddress;
		wifeAddress = _wifeAddress;
	}

	/**
	 * @dev Default function to enable sending funds to the contract.
 	 */
	function () public payable isSigned isNotDivorced {
		emit Received(msg.sender, msg.value);
	}

	/**
	 * @dev Propose a written contract.
	 * @param _writtenContractIpfsHash IPFS hash of the written contract.
	 */
	function proposeWrittenContract(string _writtenContractIpfsHash) external onlySpouse {
		require(signed == false, "Contract can not be changed any more, both spouses have already signed it");

		// Update written contract ipfs hash
		writtenContractIpfsHash = _writtenContractIpfsHash;

		emit WrittenContractProposed(_writtenContractIpfsHash, msg.sender);

		// Revoke signature of opposite spouse
		if (msg.sender == husbandAddress) {
			hasSigned[wifeAddress] = false;
		}
		if (msg.sender == wifeAddress) {
			hasSigned[husbandAddress] = false;
		}

		// Auto-sign
		if (hasSigned[msg.sender] == false) {
			hasSigned[msg.sender] = true;
			emit Signed(msg.sender);
		}
	}

	/**
	 * @dev Sign the contract.
	 */
	function signContract() external onlySpouse {
		require(isSameString(writtenContractIpfsHash, ""), "No written contract has been proposed yet");
		require(hasSigned[msg.sender] == false, "Spouse has already signed the contract");

		hasSigned[msg.sender] = true;

		emit Signed(msg.sender);

		if (hasSigned[husbandAddress] && hasSigned[wifeAddress]) {
			signed = true;
			emit ContractSigned();
		}
	}

	function pay(address _to, uint _amount) external onlySpouse isSigned isNotDivorced {
		require(_to != address(0), "Sending funds to address zero is forbidden");
		require(_amount <= address(this).balance, "Not enough funds available");

		// Send funds
		_to.transfer(_amount);

		emit Sent(_to, _amount);
	}

	/**
	 * @dev Propose to add an asset. The other spouse needs to approve this action.
	 * @param _data The asset represented as a string.
	 * @param _husbandAllocation Allocation of the husband.
	 * @param _wifeAllocation Allocation of the wife.
	 */
	function proposeAsset(string _data, uint _husbandAllocation, uint _wifeAllocation) external onlySpouse isSigned isNotDivorced {
		require(isSameString(_data, ""), "An asset must be provided");
		require(_husbandAllocation >= 0, "Invalid husband allocation");
		require(_wifeAllocation >= 0, "Invalid wife allocation");
		require((_husbandAllocation + _wifeAllocation) == 100, "Invalid allocations");

		// Add a new asset and instantly approve it by the sender
		uint id = assets.push(Asset(_data, _husbandAllocation, _wifeAllocation, false, false));
		Asset storage asset = assets[id - 1];
		asset.hasApprovedAdd[msg.sender] = true;

		emit AssetProposed(_data, msg.sender);
	}

	/**
	 * @dev Approve the addition of a prior proposed asset. The other spouse needs to approve this action.
	 */
	function approveAsset(uint _assetId) external onlySpouse isSigned isNotDivorced {
		require(_assetId > 0 && _assetId <= assets.length, "Invalid asset id");

		Asset storage asset = assets[_assetId - 1];
		require(asset.added == false, "Asset has already been added");
		require(asset.removed == false, "Asset has already been removed");
		require(asset.hasApprovedAdd[msg.sender] == false, "Already approved by spouse");

		// Approve addition by the sender
		asset.hasApprovedAdd[msg.sender] = true;

		emit AssetAddApproved(asset.data, msg.sender);

		// Check if both spouses have approved the asset
		if (asset.hasApprovedAdd[husbandAddress] && asset.hasApprovedAdd[wifeAddress]) {
			asset.added = true;
			emit AssetAdded(asset.data);
		}
	}

	/**
	 * @dev Approve the removal of a prior proposed/already added asset. The other spouse needs to approve this action.
	 */
	function removeAsset(uint _assetId) external onlySpouse isSigned isNotDivorced {
		require(_assetId > 0 && _assetId <= assets.length, "Invalid asset id");

		Asset storage asset = assets[_assetId - 1];
		require(asset.added, "Asset has not been added yet");
		require(asset.removed == false, "Asset has already been removed");
		require(asset.hasApprovedRemove[msg.sender] == false, "Removing this asset has already been approved by the spouse");

		// Approve removal by the sender
		asset.hasApprovedRemove[msg.sender] = true;

		emit AssetRemoveApproved(asset.data, msg.sender);

		// Check if both spouses have approved the removal of the asset
		if (asset.hasApprovedRemove[husbandAddress] && asset.hasApprovedRemove[wifeAddress]) {
			asset.removed = true;
			emit AssetRemoved(asset.data);
		}
	}

	/**
	 * @dev Request to divorce. The other spouse needs to approve this action.
	 */
	function divorce() external onlySpouse isSigned isNotDivorced {
		require(hasDivorced[msg.sender] == false, "Spouse has already approved to divorce");

		// Approve to divorce by the sender
		hasDivorced[msg.sender] = true;

		bool divorceApprovedByHusband = hasDivorced[husbandAddress];
		bool divorceApprovedByWife = hasDivorced[wifeAddress];

		emit DivorceApproved(msg.sender);

		// Check if both spouses have approved to divorce
		if (divorceApprovedByHusband && divorceApprovedByWife) {
			divorced = true;
			emit Divorced();

			uint balance = address(this).balance;

			if (balance != 0) {
				// Split the remaining balance of the contract 50:50
				uint balancePerSpouse = balance / 2;
				husbandAddress.transfer(balancePerSpouse);
				emit Sent(husbandAddress, balancePerSpouse);
				wifeAddress.transfer(balancePerSpouse);
				emit Sent(wifeAddress, balancePerSpouse);
			}
		}
	}

	/**
	 * @dev Return a list of all asset ids.
	 */
	function getAssetIds() external view onlySpouse returns (uint[]) {
		uint assetCount = assets.length;
		uint[] memory assetIds = new uint[](assetCount);

		for (uint i = 1; i <= assetCount; i++) {
			assetIds[i - 1] = i;
		}

		return assetIds;
	}
}
