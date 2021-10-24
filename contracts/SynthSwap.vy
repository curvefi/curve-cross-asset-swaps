# @version 0.3.0

interface AddressProvider:
    def get_registry() -> address: view
    def get_address(_id: uint256) -> address: view

interface Registry:
    def find_pool_for_coins(_from: address, _to: address) -> address: view
    def get_coin_indices(
        _pool: address,
        _from: address,
        _to: address
    ) -> (uint256, uint256, uint256): view
    def get_lp_token(_pool: address) -> address: view

interface RegistrySwap:
    def get_best_rate(_from: address, _to: address, _amount: uint256) -> (address, uint256): view

interface ERC20:
    def transferFrom(sender: address, to: address, amount: uint256): nonpayable
    def balanceOf(owner: address) -> uint256: view

interface SNXAddressResolver:
    def getAddress(name: bytes32) -> address: view

interface Synth:
    def currencyKey() -> bytes32: nonpayable

interface Exchanger:
    def getAmountsForExchange(
        sourceAmount: uint256,
        sourceCurrencyKey: bytes32,
        destinationCurrencyKey: bytes32
    ) -> (uint256, uint256, uint256): view
    def maxSecsLeftInWaitingPeriod(account: address, currencyKey: bytes32) -> uint256: view
    def settlementOwing(account: address, currencyKey: bytes32) -> (uint256, uint256): view
    def settle(user: address, currencyKey: bytes32): nonpayable

interface Settler:
    def initialize(): nonpayable
    def time_to_settle() -> uint256: view
    def convert_synth(
        _amount: uint256,
        _source_key: bytes32,
        _dest_key: bytes32
    ) -> bool: nonpayable
    def exchange(
        _pool: address,
        _initial: address,
        _target: address,
        _receiver: address,
        _amount: uint256,
        i: uint256,
        j: uint256,
        _is_underlying: uint256
    ) -> bool: payable
    def withdraw(_token: address, _receiver: address, _amount: uint256) -> bool: nonpayable

interface ERC721Receiver:
    def onERC721Received(
            _operator: address,
            _from: address,
            _token_id: uint256,
            _data: Bytes[1024]
        ) -> bytes32: view


event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    token_id: indexed(uint256)

event Approval:
    owner: indexed(address)
    approved: indexed(address)
    token_id: indexed(uint256)

event ApprovalForAll:
    owner: indexed(address)
    operator: indexed(address)
    approved: bool

event NewSettler:
    addr: address

event NewSynth:
    synth: address
    pool: address

event TokenUpdate:
    token_id: indexed(uint256)
    owner: indexed(address)
    synth: indexed(address)
    underlying_balance: uint256

event CommitOwnership:
    admin: address

event ApplyOwnership:
    admin: address

struct TokenInfo:
    owner: address
    synth: address
    underlying_balance: uint256
    time_to_settle: uint256


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383

SNX_ADDRESS_RESOLVER: constant(address) = 0x4E3b31eB0E5CB73641EE1E65E7dCEFe520bA3ef2
EXCHANGER_KEY: constant(bytes32) = 0x45786368616e6765720000000000000000000000000000000000000000000000

synth_addresses: public(address[256])
synth_count: public(uint256)

# synth -> currency key
currency_keys: HashMap[address, bytes32]

exchanger: public(Exchanger)

# token id -> owner
id_to_owner: address[4294967296]
# token id -> address approved to transfer this nft
id_to_approval: address[4294967296]
# owner -> number of nfts
owner_to_token_count: HashMap[address, uint256]
# owner -> operator -> is approved?
owner_to_operators: HashMap[address, HashMap[address, bool]]

# implementation contract used for `Settler` proxies
settler_implementation: address

# list of available token IDs
# each token ID has an associated `Settler` contract, and to reduce
# gas costs these contracts are reused. Each token ID is created from
# [12 byte nonce][20 byte settler address]. The nonce starts at 0 and is
# incremented each time the token ID is "freed" (added to `available_token_ids`)
available_settlers: address[4294967296]
available_settler_count: uint256
total_settlers: public(uint256)

id_to_settler: address[4294967296]
id_to_synth: address[4294967296]


owner_to_token_ids: HashMap[address, uint256[4294967296]]

# total number of swaps executed in this contract
total_swaps: public(uint256)

# token id -> is synth settled?
is_settled: public(HashMap[uint256, bool])

# token -> synth to swap to/for
# necessary in case someone deploys an incorrect factory pool and borks
# our ability to correctly route swaps (i'm looking at you, ibEUR)
target_synth: public(HashMap[address, address])

owner: public(address)
future_owner: public(address)

@external
def __init__(_settler_implementation: address, _settler_count: uint256):
    """
    @notice Contract constructor
    @param _settler_implementation `Settler` implementation deployment
    """
    self.owner = msg.sender

    self.settler_implementation = _settler_implementation
    self.exchanger = Exchanger(SNXAddressResolver(SNX_ADDRESS_RESOLVER).getAddress(EXCHANGER_KEY))

    # deploy settler contracts immediately
    self.available_settler_count = _settler_count
    self.total_settlers = _settler_count
    for i in range(100):
        if i == _settler_count:
            break
        settler: address = create_forwarder_to(_settler_implementation)
        Settler(settler).initialize()
        self.available_settlers[i] = settler
        log NewSettler(settler)


@view
@external
def name() -> String[32]:
    return "Curve SynthSwap 2"


@view
@external
def symbol() -> String[32]:
    return "CRV/SS-2"


@view
@external
def supportsInterface(_interface_id: bytes32) -> bool:
    """
    @dev Interface identification is specified in ERC-165
    @param _interface_id Id of the interface
    @return bool Is interface supported?
    """
    return _interface_id in [
        0x0000000000000000000000000000000000000000000000000000000001ffc9a7,  # ERC165
        0x0000000000000000000000000000000000000000000000000000000080ac58cd,  # ERC721
    ]


@view
@external
def totalSupply() -> uint256:
    return self.total_settlers - self.available_settler_count


@view
@external
def balanceOf(_owner: address) -> uint256:
    """
    @notice Return the number of NFTs owned by `_owner`
    @dev Reverts if `_owner` is the zero address. NFTs assigned
         to the zero address are considered invalid
    @param _owner Address for whom to query the balance
    @return uint256 Number of NFTs owned by `_owner`
    """
    assert _owner != ZERO_ADDRESS
    return self.owner_to_token_count[_owner]


@view
@external
def ownerOf(_token_id: uint256) -> address:
    """
    @notice Return the address of the owner of the NFT
    @dev Reverts if `_token_id` is not a valid NFT
    @param _token_id The identifier for an NFT
    @return address NFT owner
    """
    owner: address = self.id_to_owner[_token_id]
    assert owner != ZERO_ADDRESS
    return owner


@view
@external
def tokenOfOwnerByIndex(_owner: address, _index: uint256) -> uint256:
    assert _owner != ZERO_ADDRESS
    assert self.owner_to_token_count[_owner] > _index
    return self.owner_to_token_ids[_owner][_index]


@view
@external
def getApproved(_token_id: uint256) -> address:
    """
    @notice Get the approved address for a single NFT
    @dev Reverts if `_token_id` is not a valid NFT
    @param _token_id ID of the NFT to query the approval of
    @return address Address approved to transfer this NFT
    """
    assert self.id_to_owner[_token_id] != ZERO_ADDRESS
    return self.id_to_approval[_token_id]


@view
@external
def isApprovedForAll(_owner: address, _operator: address) -> bool:
    """
    @notice Check if `_operator` is an approved operator for `_owner`
    @param _owner The address that owns the NFTs
    @param _operator The address that acts on behalf of the owner
    @return bool Is operator approved?
    """
    return self.owner_to_operators[_owner][_operator]


@internal
def _transfer(_from: address, _to: address, _token_id: uint256, _caller: address):
    assert _from != ZERO_ADDRESS, "Cannot send from zero address"
    assert _to != ZERO_ADDRESS, "Cannot send to zero address"
    owner: address = self.id_to_owner[_token_id]
    assert owner == _from, "Incorrect owner for Token ID"

    approved_for: address = self.id_to_approval[_token_id]
    if _caller != _from:
        assert approved_for == _caller or self.owner_to_operators[owner][_caller], "Caller is not owner or operator"

    if approved_for != ZERO_ADDRESS:
        self.id_to_approval[_token_id] = ZERO_ADDRESS

    self.id_to_owner[_token_id] = _to
    self.owner_to_token_count[_from] -= 1
    self.owner_to_token_count[_to] += 1

    log Transfer(_from, _to, _token_id)


@external
def transferFrom(_from: address, _to: address, _token_id: uint256):
    """
    @notice Transfer ownership of `_token_id` from `_from` to `_to`
    @dev Reverts unless `msg.sender` is the current owner, an
         authorized operator, or the approved address for `_token_id`
         Reverts if `_to` is the zero address
    @param _from The current owner of `_token_id`
    @param _to Address to transfer the NFT to
    @param _token_id ID of the NFT to transfer
    """
    self._transfer(_from, _to, _token_id, msg.sender)


@external
def safeTransferFrom(
    _from: address,
    _to: address,
    _token_id: uint256,
    _data: Bytes[1024]=b""
):
    """
    @notice Transfer ownership of `_token_id` from `_from` to `_to`
    @dev If `_to` is a smart contract, it must implement the `onERC721Received` function
         and return the value `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    @param _from The current owner of `_token_id`
    @param _to Address to transfer the NFT to
    @param _token_id ID of the NFT to transfer
    @param _data Additional data with no specified format, sent in call to `_to`
    """
    self._transfer(_from, _to, _token_id, msg.sender)

    if _to.is_contract:
        response: bytes32 = ERC721Receiver(_to).onERC721Received(msg.sender, _from, _token_id, _data)
        assert response == 0x150b7a0200000000000000000000000000000000000000000000000000000000


@external
def approve(_approved: address, _token_id: uint256):
    """
    @notice Set or reaffirm the approved address for an NFT.
            The zero address indicates there is no approved address.
    @dev Reverts unless `msg.sender` is the current NFT owner, or an authorized
         operator of the current owner. Reverts if `_token_id` is not a valid NFT.
    @param _approved Address to be approved for the given NFT ID
    @param _token_id ID of the token to be approved
    """
    owner: address = self.id_to_owner[_token_id]

    if msg.sender != self.id_to_owner[_token_id]:
        assert owner != ZERO_ADDRESS, "Unknown Token ID"
        assert self.owner_to_operators[owner][msg.sender], "Caller is not owner or operator"

    self.id_to_approval[_token_id] = _approved
    log Approval(owner, _approved, _token_id)


@external
def setApprovalForAll(_operator: address, _approved: bool):
    """
    @notice Enable or disable approval for a third party ("operator") to manage all
         NFTs owned by `msg.sender`.
    @param _operator Address to set operator authorization for.
    @param _approved True if the operators is approved, False to revoke approval.
    """
    self.owner_to_operators[msg.sender][_operator] = _approved
    log ApprovalForAll(msg.sender, _operator, _approved)


@payable
@external
def swap_into_synth(
    _amount: uint256,
    _route: address[4],
    _indices: uint256[4],
    _min_received: uint256,
    _receiver: address = msg.sender
) -> uint256:
    """
    @notice Perform a cross-asset swap between `_from` and `_synth`
    @dev Synth swaps require a settlement time to complete and so the newly
         generated synth cannot immediately be transferred onward. Calling
         this function mints an NFT which represents ownership of the generated
         synth. Once the settlement time has passed, the owner may claim the
         synth by calling to `swap_from_synth` or `withdraw`.
    @return uint256 NFT token ID
    """
    settler: address = ZERO_ADDRESS

    count: uint256 = self.available_settler_count
    token_id: uint256 = self.total_swaps + 1
    self.total_swaps = token_id
    if count == 0:
        # if there are no availale settler contracts we must deploy a new one
        settler = create_forwarder_to(self.settler_implementation)
        Settler(settler).initialize()
        log NewSettler(settler)
        self.total_settlers += 1
    else:
        count -= 1
        settler = self.available_settlers[count]
        self.available_settler_count = count

    # perform the first stableswap, if required
    amount: uint256 = _amount
    if _route[1] != ZERO_ADDRESS:
        ERC20(_route[0]).transferFrom(msg.sender, settler, _amount)  # dev: insufficient amount
        Settler(settler).exchange(
            _route[1],      # pool
            _route[0],      # initial asset
            _route[2],      # target asset
            ZERO_ADDRESS,   # receiver (empty to keep the swap balance within the settler)
            _amount,        # amount
            _indices[0],    # i
            _indices[1],    # j
            _indices[2],    # is_underlying
            value=msg.value
        )
        amount = ERC20(_route[2]).balanceOf(settler)
    else:
        assert msg.value == 0
        ERC20(_route[2]).transferFrom(msg.sender, settler, _amount)  # dev: insufficient amount

    # use Synthetix to convert initial synth into the target synth
    Settler(settler).convert_synth(
        amount,
        convert(_indices[3], bytes32),
        self.currency_keys[_route[3]],
    )
    final_balance: uint256 = ERC20(_route[2]).balanceOf(settler)
    assert final_balance >= _min_received, "Rekt by slippage"

    # mint an NFT to represent the unsettled conversion
    self.id_to_owner[token_id] = _receiver
    count = self.owner_to_token_count[_receiver]
    self.owner_to_token_ids[_receiver][count] = token_id
    self.owner_to_token_count[msg.sender] = count + 1
    self.id_to_settler[token_id] = settler
    self.id_to_synth[token_id] = _route[3]

    log Transfer(ZERO_ADDRESS, _receiver, token_id)

    log TokenUpdate(token_id, _receiver, _route[2], final_balance)

    return token_id


@external
def swap_from_synth(
    _token_id: uint256,
    _route: address[2],
    _indices: uint256[4],
    _min_received: uint256,
    _receiver: address = msg.sender
) -> uint256:
    """
    @notice Swap the synth represented by an NFT into another asset.
    @dev Callable by the owner or operator of `_token_id` after the synth settlement
         period has passed. If `_amount` is equal to the entire balance within
         the NFT, the NFT is burned.
    @return uint256 Synth balance remaining in `_token_id`
    """
    owner: address = self.id_to_owner[_token_id]
    if msg.sender != self.id_to_owner[_token_id]:
        assert owner != ZERO_ADDRESS, "Unknown Token ID"
        assert (
            self.owner_to_operators[owner][msg.sender] or
            msg.sender == self.id_to_approval[_token_id]
        ), "Caller is not owner or operator"

    settler: address = self.id_to_settler[_token_id]
    assert settler != ZERO_ADDRESS
    synth: address = self.id_to_synth[_token_id]

    # ensure the synth is settled prior to swapping
    if not self.is_settled[_token_id]:
        self.exchanger.settle(settler, self.currency_keys[synth])
        self.is_settled[_token_id] = True

    if _route[0] == ZERO_ADDRESS:
        Settler(settler).withdraw(synth, _receiver, _indices[0])
    else:
        Settler(settler).exchange(
            _route[0],      # pool
            synth,          # initial asset
            _route[1],      # target asset
            _receiver,      # receiver
            _indices[0],    # amount
            _indices[1],    # i
            _indices[2],    # j
            _indices[3]     # is_underlying
        )
    remaining: uint256 = ERC20(synth).balanceOf(settler)

    # if the balance of the synth within the NFT is now zero, burn the NFT
    if remaining == 0:
        self.id_to_owner[_token_id] = ZERO_ADDRESS
        self.id_to_approval[_token_id] = ZERO_ADDRESS
        self.is_settled[_token_id] = False
        count: uint256 = self.available_settler_count
        self.available_settlers[count] = settler
        self.available_settler_count = count + 1

        self.id_to_settler[_token_id] = ZERO_ADDRESS

        count = self.owner_to_token_count[msg.sender] - 1
        self.owner_to_token_count[msg.sender] = count
        for i in range(4294967296):
            if i == count:
                assert self.owner_to_token_ids[msg.sender][i] == _token_id
                self.owner_to_token_ids[msg.sender][i] = 0
                break
            if self.owner_to_token_ids[msg.sender][i] == _token_id:
                self.owner_to_token_ids[msg.sender][i] = self.owner_to_token_ids[msg.sender][count]
                break

        owner = ZERO_ADDRESS
        synth = ZERO_ADDRESS
        log Transfer(msg.sender, ZERO_ADDRESS, _token_id)

    log TokenUpdate(_token_id, owner, synth, remaining)

    return remaining


@view
@internal
def _get_indices(_pool: address, _initial: address, _target: address) -> (uint256, uint256, uint256):
    # check if a pool exists in the main registry or the factory
    registry: address = AddressProvider(ADDRESS_PROVIDER).get_registry()
    if Registry(registry).get_lp_token(_pool) == ZERO_ADDRESS:
        registry = AddressProvider(ADDRESS_PROVIDER).get_address(3)
    return Registry(registry).get_coin_indices(_pool, _initial, _target)

@view
@external
def get_swap_into_routing(
    _initial: address,
    _target: address,
    _amount: uint256
) -> (address[4], uint256[4], uint256):
    """
    @notice Get routing data for a cross-asset exchange.
    @dev Outputs from this function are used as inputs when calling `exchange`.
    @param _initial Address of the initial token being swapped.
    @param _target Address of the token to be received in the swap.
    @param _amount Amount of `_initial` to swap.
    @return _route Array of token and pool addresses used within the swap,
                    Array of `i` and `j` inputs used for individual swaps.
                    Expected amount of the output token to be received.
    """

    # route is [initial coin, stableswap, synth input, synth output]
    route: address[4] = empty(address[4])

    # indices is [(i, j, is_underlying), input synth currency key]
    indices: uint256[4] = empty(uint256[4])

    synth_input: address = ZERO_ADDRESS
    synth_output: address = ZERO_ADDRESS

    amount: uint256 = _amount
    swaps: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)

    if self.currency_keys[_initial] != EMPTY_BYTES32:
        synth_input = _initial
    else:
        market: address = ZERO_ADDRESS
        if self.target_synth[_initial] != ZERO_ADDRESS:
            synth_input = self.target_synth[_initial]
            market, amount = RegistrySwap(swaps).get_best_rate(_initial, synth_input, _amount)
        else:
            for i in range(256):
                if i == self.synth_count:
                    raise "No path from input to synth"
                synth: address = self.synth_addresses[i]
                market, amount = RegistrySwap(swaps).get_best_rate(_initial, synth, _amount)
                if market != ZERO_ADDRESS:
                    synth_input = synth
                    break
        indices[0], indices[1], indices[2] = self._get_indices(market, _initial, synth_input)
        route[0] = _initial
        route[1] = market

    if self.currency_keys[_target] != EMPTY_BYTES32:
        synth_output = _target
        amount = self.exchanger.getAmountsForExchange(
            amount,
            self.currency_keys[synth_input],
            self.currency_keys[synth_output],
        )[0]
    else:
        if self.target_synth[_target] != ZERO_ADDRESS:
            synth_output = self.target_synth[_target]
        else:
            for i in range(256):
                if i == self.synth_count:
                    raise "No path from synth to target"
                synth: address = self.synth_addresses[i]
                if RegistrySwap(swaps).get_best_rate(synth, _target, 10**18)[0] != ZERO_ADDRESS:
                    synth_output = synth
                    break
        amount = self.exchanger.getAmountsForExchange(
            amount,
            self.currency_keys[synth_input],
            self.currency_keys[synth_output],
        )[0]

    assert synth_input != synth_output, "No synth swap required"
    route[2] = synth_input
    route[3] = synth_output
    indices[3] = convert(self.currency_keys[synth_input], uint256)

    return route, indices, amount


@view
@external
def token_info(_token_id: uint256) -> TokenInfo:
    """
    @notice Get information about the synth represented by an NFT
    @param _token_id NFT token ID to query info about
    @return NFT owner
            Address of synth within the NFT
            Balance of the synth
            Max settlement time in seconds
    """
    info: TokenInfo = empty(TokenInfo)
    info.owner = self.id_to_owner[_token_id]
    assert info.owner != ZERO_ADDRESS

    settler: address = self.id_to_settler[_token_id]
    info.synth = self.id_to_synth[_token_id]
    info.underlying_balance = ERC20(info.synth).balanceOf(settler)

    if not self.is_settled[_token_id]:
        currency_key: bytes32 = self.currency_keys[info.synth]
        reclaim: uint256 = 0
        rebate: uint256 = 0
        reclaim, rebate = self.exchanger.settlementOwing(settler, currency_key)
        info.underlying_balance = info.underlying_balance - reclaim + rebate
        info.time_to_settle = self.exchanger.maxSecsLeftInWaitingPeriod(settler, currency_key)

    return info


@view
@external
def get_swap_out_routing(
    _token_id: uint256,
    _target: address,
    _amount: uint256 = 0
) -> (address[2], uint256[4], uint256):
    """
    @notice Get routing data for a cross-asset exchange.
    @dev Outputs from this function are used as inputs when calling `exchange`.
    """

    # route is [stableswap, target coin]
    route: address[2] = empty(address[2])

    # indices is [amount after settlement, (i, j, is_underlying)]
    indices: uint256[4] = empty(uint256[4])

    settler: address = self.id_to_settler[_token_id]
    assert settler != ZERO_ADDRESS
    synth: address = self.id_to_synth[_token_id]
    currency_key: bytes32 = self.currency_keys[synth]
    amount: uint256 = _amount
    if amount == 0:
        amount = ERC20(synth).balanceOf(settler)
        reclaim: uint256 = 0
        rebate: uint256 = 0
        reclaim, rebate = self.exchanger.settlementOwing(settler, currency_key)
        amount = amount - reclaim + rebate

    indices[0] = amount

    market: address = ZERO_ADDRESS
    if _target != synth:
        route[1] = _target
        swaps: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)
        route[0], amount = RegistrySwap(swaps).get_best_rate(synth, _target, amount)
        indices[1], indices[2], indices[3] =self._get_indices(route[0], synth, _target)

    return route, indices, amount


@view
@external
def can_route(_initial: address, _target: address) -> bool:
    """
    @notice Check if a route is available between two tokens.
    @param _initial Address of the initial token being swapped.
    @param _target Address of the token to be received in the swap.
    @return bool Is route available?
    """

    synth_input: address = ZERO_ADDRESS
    synth_output: address = ZERO_ADDRESS
    swaps: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)

    if self.currency_keys[_initial] != EMPTY_BYTES32:
        synth_input = _initial
    elif self.target_synth[_initial] != ZERO_ADDRESS:
        synth_input = self.target_synth[_initial]
    else:
        for i in range(256):
            if i == self.synth_count:
                return False
            synth: address = self.synth_addresses[i]
            if RegistrySwap(swaps).get_best_rate(_initial, synth, 10**18)[0] != ZERO_ADDRESS:
                synth_input = synth
                break

    if self.currency_keys[_target] != EMPTY_BYTES32:
        synth_output = _target
    elif self.target_synth[_target] != ZERO_ADDRESS:
        synth_output = self.target_synth[_initial]
    else:
        for i in range(256):
            if i == self.synth_count:
                return False
            synth: address = self.synth_addresses[i]
            if RegistrySwap(swaps).get_best_rate(synth, _target, 10**18)[0] != ZERO_ADDRESS:
                synth_output = synth
                break

    return synth_input != synth_output


@external
def rebuildCache() -> bool:
    """
    @notice Update the current address of the SNX Exchanger contract
    @dev The SNX exchanger address is kept in the local contract storage to reduce gas costs.
         If this address changes, contract will stop working until the local address is updated.
         Synthetix automates this process within their own architecture by exposing a `rebuildCache`
         method in their own contracts, and calling them all to update via `AddressResolver.rebuildCaches`,
         so we use the same API in order to be able to receive updates from them as well.
         https://docs.synthetix.io/contracts/source/contracts/AddressResolver/#rebuildcaches
    @return boolean, was Exchanger address up-to-date?
    """
    exchanger: address = SNXAddressResolver(SNX_ADDRESS_RESOLVER).getAddress(EXCHANGER_KEY)
    if self.exchanger != Exchanger(exchanger):
        self.exchanger = Exchanger(exchanger)
        return False
    return True


@external
def add_synths(_synths: address[10]):
    assert msg.sender == self.owner  # dev: admin only
    count: uint256 = self.synth_count
    for synth in _synths:
        if synth == ZERO_ADDRESS:
            break
        assert self.currency_keys[synth] == EMPTY_BYTES32
        self.currency_keys[synth] = Synth(synth).currencyKey()
        self.synth_addresses[count] = synth
        count += 1
    self.synth_count = count


@external
def set_target_synth(_token: address, _synth: address):
    assert msg.sender == self.owner  # dev: admin only
    self.target_synth[_token] = _synth



@external
def commit_transfer_ownership(addr: address):
    """
    @notice Transfer ownership of GaugeController to `addr`
    @param addr Address to have ownership transferred to
    """
    assert msg.sender == self.owner  # dev: admin only

    self.future_owner = addr
    log CommitOwnership(addr)


@external
def accept_transfer_ownership():
    """
    @notice Accept a pending ownership transfer
    """
    _admin: address = self.future_owner
    assert msg.sender == _admin  # dev: future admin only

    self.owner = _admin
    log ApplyOwnership(_admin)
