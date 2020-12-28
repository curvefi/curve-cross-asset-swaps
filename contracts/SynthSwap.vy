# @version 0.2.8

from vyper.interfaces import ERC20
from vyper.interfaces import ERC721

implements: ERC721


interface AddressProvider:
    def get_registry() -> address: view
    def get_address(_id: uint256) -> address: view

interface Registry:
    def get_coins(_pool: address) -> address[8]: view

interface RegistrySwap:
    def exchange(
        _pool: address,
        _from: address,
        _to: address,
        _amount: uint256,
        _expected: uint256,
        _receiver: address,
    ) -> uint256: payable

interface Synth:
    def currencyKey() -> bytes32: nonpayable

interface Settler:
    def initialize(): nonpayable
    def synth() -> address: view
    def exchange_synth(_initial: address, _target: address, _amount: uint256) -> bool: nonpayable
    def settle_and_swap(
        _target: address,
        _pool: address,
        _amount: uint256,
        _expected: uint256,
        _receiver: address,
    ) -> uint256: nonpayable
    def withdraw(_receiver: address, _amount: uint256) -> uint256: nonpayable
    def settle() -> bool: nonpayable

interface ERC721Receiver:
    def onERC721Received(
            _operator: address,
            _from: address,
            _tokenId: uint256,
            _data: Bytes[1024]
        ) -> bytes32: view


event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    tokenId: indexed(uint256)

event Approval:
    owner: indexed(address)
    approved: indexed(address)
    tokenId: indexed(uint256)

event ApprovalForAll:
    owner: indexed(address)
    operator: indexed(address)
    approved: bool


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383

# @dev Mapping from NFT ID to the address that owns it.
idToOwner: HashMap[uint256, address]

# @dev Mapping from NFT ID to approved address.
idToApprovals: HashMap[uint256, address]

# @dev Mapping from owner address to count of his tokens.
ownerToNFTokenCount: HashMap[address, uint256]

# @dev Mapping from owner address to mapping of operator addresses.
ownerToOperators: HashMap[address, HashMap[address, bool]]

settler_implementation: address
settler_proxies: address[4294967296]
settler_count: uint256

# synth address -> curve pool
synth_pools: HashMap[address, address]
# coin -> synth
swappable_synth: HashMap[address, address]
# coin -> spender -> is approved?
is_approved: HashMap[address, HashMap[address, bool]]


@external
def __init__(_settler_implementation: address):
    """
    @dev Contract constructor.
    """
    self.settler_implementation = _settler_implementation


@view
@external
def supportsInterface(_interfaceID: bytes32) -> bool:
    """
    @dev Interface identification is specified in ERC-165.
    @param _interfaceID Id of the interface
    """
    return _interfaceID in [
        0x0000000000000000000000000000000000000000000000000000000001ffc9a7,  # ERC165
        0x0000000000000000000000000000000000000000000000000000000080ac58cd,  # ERC721
    ]


@view
@external
def balanceOf(_owner: address) -> uint256:
    """
    @dev Returns the number of NFTs owned by `_owner`.
         Throws if `_owner` is the zero address. NFTs assigned to the zero address are considered invalid.
    @param _owner Address for whom to query the balance.
    """
    assert _owner != ZERO_ADDRESS
    return self.ownerToNFTokenCount[_owner]


@view
@external
def ownerOf(_tokenId: uint256) -> address:
    """
    @dev Returns the address of the owner of the NFT.
         Throws if `_tokenId` is not a valid NFT.
    @param _tokenId The identifier for an NFT.
    """
    owner: address = self.idToOwner[_tokenId]
    # Throws if `_tokenId` is not a valid NFT
    assert owner != ZERO_ADDRESS
    return owner


@view
@external
def getApproved(_tokenId: uint256) -> address:
    """
    @dev Get the approved address for a single NFT.
         Throws if `_tokenId` is not a valid NFT.
    @param _tokenId ID of the NFT to query the approval of.
    """
    # Throws if `_tokenId` is not a valid NFT
    assert self.idToOwner[_tokenId] != ZERO_ADDRESS
    return self.idToApprovals[_tokenId]


@view
@external
def isApprovedForAll(_owner: address, _operator: address) -> bool:
    """
    @dev Checks if `_operator` is an approved operator for `_owner`.
    @param _owner The address that owns the NFTs.
    @param _operator The address that acts on behalf of the owner.
    """
    return (self.ownerToOperators[_owner])[_operator]


### TRANSFER FUNCTION HELPERS ###

@view
@internal
def _isApprovedOrOwner(_spender: address, _tokenId: uint256) -> bool:
    """
    @dev Returns whether the given spender can transfer a given token ID
    @param spender address of the spender to query
    @param tokenId uint256 ID of the token to be transferred
    @return bool whether the msg.sender is approved for the given token ID,
        is an operator of the owner, or is the owner of the token
    """
    owner: address = self.idToOwner[_tokenId]
    spenderIsOwner: bool = owner == _spender
    spenderIsApproved: bool = _spender == self.idToApprovals[_tokenId]
    spenderIsApprovedForAll: bool = (self.ownerToOperators[owner])[_spender]
    return (spenderIsOwner or spenderIsApproved) or spenderIsApprovedForAll


@internal
def _addTokenTo(_to: address, _tokenId: uint256):
    """
    @dev Add a NFT to a given address
         Throws if `_tokenId` is owned by someone.
    """
    # Throws if `_tokenId` is owned by someone
    assert self.idToOwner[_tokenId] == ZERO_ADDRESS
    # Change the owner
    self.idToOwner[_tokenId] = _to
    # Change count tracking
    self.ownerToNFTokenCount[_to] += 1


@internal
def _removeTokenFrom(_from: address, _tokenId: uint256):
    """
    @dev Remove a NFT from a given address
         Throws if `_from` is not the current owner.
    """
    # Throws if `_from` is not the current owner
    assert self.idToOwner[_tokenId] == _from
    # Change the owner
    self.idToOwner[_tokenId] = ZERO_ADDRESS
    # Change count tracking
    self.ownerToNFTokenCount[_from] -= 1


@internal
def _clearApproval(_owner: address, _tokenId: uint256):
    """
    @dev Clear an approval of a given address
         Throws if `_owner` is not the current owner.
    """
    # Throws if `_owner` is not the current owner
    assert self.idToOwner[_tokenId] == _owner
    if self.idToApprovals[_tokenId] != ZERO_ADDRESS:
        # Reset approvals
        self.idToApprovals[_tokenId] = ZERO_ADDRESS


@internal
def _transferFrom(_from: address, _to: address, _tokenId: uint256, _sender: address):
    """
    @dev Exeute transfer of a NFT.
         Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
         address for this NFT. (NOTE: `msg.sender` not allowed in private function so pass `_sender`.)
         Throws if `_to` is the zero address.
         Throws if `_from` is not the current owner.
         Throws if `_tokenId` is not a valid NFT.
    """
    # Check requirements
    assert self._isApprovedOrOwner(_sender, _tokenId)
    # Throws if `_to` is the zero address
    assert _to != ZERO_ADDRESS
    # Clear approval. Throws if `_from` is not the current owner
    self._clearApproval(_from, _tokenId)
    # Remove NFT. Throws if `_tokenId` is not a valid NFT
    self._removeTokenFrom(_from, _tokenId)
    # Add NFT
    self._addTokenTo(_to, _tokenId)
    # Log the transfer
    log Transfer(_from, _to, _tokenId)


### TRANSFER FUNCTIONS ###

@external
def transferFrom(_from: address, _to: address, _tokenId: uint256):
    """
    @dev Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
         address for this NFT.
         Throws if `_from` is not the current owner.
         Throws if `_to` is the zero address.
         Throws if `_tokenId` is not a valid NFT.
    @notice The caller is responsible to confirm that `_to` is capable of receiving NFTs or else
            they maybe be permanently lost.
    @param _from The current owner of the NFT.
    @param _to The new owner.
    @param _tokenId The NFT to transfer.
    """
    self._transferFrom(_from, _to, _tokenId, msg.sender)


@external
def safeTransferFrom(
        _from: address,
        _to: address,
        _tokenId: uint256,
        _data: Bytes[1024]=b""
    ):
    """
    @dev Transfers the ownership of an NFT from one address to another address.
         Throws unless `msg.sender` is the current owner, an authorized operator, or the
         approved address for this NFT.
         Throws if `_from` is not the current owner.
         Throws if `_to` is the zero address.
         Throws if `_tokenId` is not a valid NFT.
         If `_to` is a smart contract, it calls `onERC721Received` on `_to` and throws if
         the return value is not `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
         NOTE: bytes4 is represented by bytes32 with padding
    @param _from The current owner of the NFT.
    @param _to The new owner.
    @param _tokenId The NFT to transfer.
    @param _data Additional data with no specified format, sent in call to `_to`.
    """
    self._transferFrom(_from, _to, _tokenId, msg.sender)
    if _to.is_contract: # check if `_to` is a contract address
        returnValue: bytes32 = ERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data)
        # Throws if transfer destination is a contract which does not implement 'onERC721Received'
        assert returnValue == method_id("onERC721Received(address,address,uint256,bytes)", output_type=bytes32)


@external
def approve(_approved: address, _tokenId: uint256):
    """
    @dev Set or reaffirm the approved address for an NFT. The zero address indicates there is no approved address.
         Throws unless `msg.sender` is the current NFT owner, or an authorized operator of the current owner.
         Throws if `_tokenId` is not a valid NFT. (NOTE: This is not written the EIP)
         Throws if `_approved` is the current owner. (NOTE: This is not written the EIP)
    @param _approved Address to be approved for the given NFT ID.
    @param _tokenId ID of the token to be approved.
    """
    owner: address = self.idToOwner[_tokenId]
    # Throws if `_tokenId` is not a valid NFT
    assert owner != ZERO_ADDRESS
    # Throws if `_approved` is the current owner
    assert _approved != owner
    # Check requirements
    senderIsOwner: bool = self.idToOwner[_tokenId] == msg.sender
    senderIsApprovedForAll: bool = (self.ownerToOperators[owner])[msg.sender]
    assert (senderIsOwner or senderIsApprovedForAll)
    # Set the approval
    self.idToApprovals[_tokenId] = _approved
    log Approval(owner, _approved, _tokenId)


@external
def setApprovalForAll(_operator: address, _approved: bool):
    """
    @dev Enables or disables approval for a third party ("operator") to manage all of
         `msg.sender`'s assets. It also emits the ApprovalForAll event.
         Throws if `_operator` is the `msg.sender`. (NOTE: This is not written the EIP)
    @notice This works even if sender doesn't own any tokens at the time.
    @param _operator Address to add to the set of authorized operators.
    @param _approved True if the operators is approved, false to revoke approval.
    """
    # Throws if `_operator` is the `msg.sender`
    assert _operator != msg.sender
    self.ownerToOperators[msg.sender][_operator] = _approved
    log ApprovalForAll(msg.sender, _operator, _approved)


@external
def swap_into_synth(
    _from: address,
    _synth: address,
    _amount: uint256,
    _expected: uint256,
    _receiver: address = msg.sender,
    _token_id: uint256 = 0,
) -> uint256:

    settler: address = convert(_token_id, address)
    if settler == ZERO_ADDRESS:
        count: uint256 = self.settler_count
        if count == 0:
            settler = create_forwarder_to(self.settler_implementation)
            Settler(settler).initialize()
        else:
            count -= 1
            settler = self.settler_proxies[count]
            self.settler_count = count
    else:
        assert msg.sender == self.idToOwner[_token_id]
        assert msg.sender == _receiver
        assert Settler(settler).synth() == _synth

    ERC20(_from).transferFrom(msg.sender, self, _amount)

    intermediate_synth: address = self.swappable_synth[_from]
    pool: address = self.synth_pools[intermediate_synth]

    registry_swap: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)
    if not self.is_approved[_from][registry_swap]:
        ERC20(_from).approve(registry_swap, MAX_UINT256)
        self.is_approved[_from][registry_swap] = True

    received: uint256 = RegistrySwap(registry_swap).exchange(
        pool,
        _from,
        intermediate_synth,
        _amount,
        _expected,
        settler
    )
    Settler(settler).exchange_synth(intermediate_synth, _synth, received)

    token_id: uint256 = convert(settler, uint256)
    if _token_id == 0:
        self.idToOwner[token_id] = _receiver
        self.ownerToNFTokenCount[_receiver] += 1
        log Transfer(ZERO_ADDRESS, _receiver, token_id)

    return token_id


@external
def swap_from_synth(
    _token_id: uint256,
    _target: address,
    _amount: uint256,
    _expected: uint256,
    _receiver: address = msg.sender,
) -> uint256:
    assert msg.sender == self.idToOwner[_token_id]

    settler: address = convert(_token_id, address)

    synth: address = self.swappable_synth[_target]
    pool: address = self.synth_pools[synth]

    remaining_balance: uint256 = Settler(settler).settle_and_swap(_target, pool, _amount, _expected, _receiver)

    if remaining_balance == 0:
        self.idToOwner[_token_id] = ZERO_ADDRESS
        self.idToApprovals[_token_id] = ZERO_ADDRESS
        self.ownerToNFTokenCount[msg.sender] -= 1
        count: uint256 = self.settler_count
        self.settler_proxies[count] = settler
        self.settler_count = count + 1
        log Transfer(msg.sender, ZERO_ADDRESS, _token_id)

    return remaining_balance


@external
def withdraw(_token_id: uint256, _amount: uint256, _receiver: address = msg.sender) -> uint256:
    assert msg.sender == self.idToOwner[_token_id]

    settler: address = convert(_token_id, address)
    remaining_balance: uint256 = Settler(settler).withdraw(_receiver, _amount)

    if remaining_balance == 0:
        self.idToOwner[_token_id] = ZERO_ADDRESS
        self.idToApprovals[_token_id] = ZERO_ADDRESS
        self.ownerToNFTokenCount[msg.sender] -= 1
        count: uint256 = self.settler_count
        self.settler_proxies[count] = settler
        self.settler_count = count + 1
        log Transfer(msg.sender, ZERO_ADDRESS, _token_id)

    return remaining_balance


@external
def settle(_token_id: uint256) -> bool:
    settler: address = convert(_token_id, address)
    Settler(settler).settle()

    return True


@external
def add_synth(_synth: address, _pool: address):
    assert self.synth_pools[_synth] == ZERO_ADDRESS
    Synth(_synth).currencyKey()

    registry: address = AddressProvider(ADDRESS_PROVIDER).get_registry()
    pool_coins: address[8] = Registry(registry).get_coins(_pool)

    has_synth: bool = False
    for coin in pool_coins:
        if coin == ZERO_ADDRESS:
            assert has_synth
            break
        if coin == _synth:
            self.synth_pools[_synth] = _pool
            has_synth = True
        else:
            self.swappable_synth[coin] = _synth
