# @version 0.3.0
"""
@title Curve x Synthetix Cross Asset Swaps
@license MIT
@author CurveFi
"""
from vyper.interfaces import ERC20


interface AddressProvider:
    def get_registry() -> address: view
    def get_address(_idx: uint256) -> address: view

interface Registry:
    # actually returns an address
    def get_lp_token(_pool: address) -> uint256: view
    # actually returns (int128, int128, bool)
    def get_coin_indices(_pool: address, _from: address, _to: address) -> uint256[3]: view
    def get_coin_swap_complement(_coin: address, _idx: uint256) -> address: view

interface RegistryExchange:
    def get_best_rate(_from: address, _to: address, _amount: uint256) -> (address, uint256): view

interface ERC721Receiver:
    def onERC721Received(_operator: address, _from: address, _token_id: uint256, _data: Bytes[512]) -> uint256: nonpayable

interface Settler:
    def initialize(): nonpayable
    def exchange(
        _pool: address,
        _from: address,
        _to: address,
        _receiver: address,
        _amount: uint256,
        _i: uint256,
        _j: uint256,
        _use_underlying: uint256
    ): payable
    def convert_synth(_dx: uint256, _src_key: bytes32, _dst_key: bytes32): nonpayable

interface SynthExchanger:
    # actually returns (uint256, uint256, uint256)
    def getAmountsForExchange(_amount: uint256, _source_key: bytes32, _dest_key: bytes32) -> uint256: view

interface SNXAddressResolver:
    # is it just me or is this a weird address resolution system
    def getAddress(_name: bytes32) -> address: view

interface Synth:
    def currencyKey() -> bytes32: view


event Approval:
    _owner: indexed(address)
    _approved: indexed(address)
    _token_id: indexed(uint256)

event ApprovalForAll:
    _owner: indexed(address)
    _operator: indexed(address)
    _approved: bool

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _token_id: indexed(uint256)

event NewSettler:
    _settler: indexed(address)


# swap data used when performing an exchange
struct SwapData:
    _pool: address
    _from: address
    _to: address
    _i: uint256
    _j: uint256
    _use_underlying: uint256


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383
SNX_ADDRESS_RESOLVER: constant(address) = 0x4E3b31eB0E5CB73641EE1E65E7dCEFe520bA3ef2
# "0x" + b"Exchanger".hex() + "00" * 23
EXCHANGER_KEY: constant(bytes32) = 0x45786368616e6765720000000000000000000000000000000000000000000000
ETH_ADDRESS: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE


balanceOf: public(HashMap[address, uint256])
getApproved: public(HashMap[uint256, address])
isApprovedForAll: public(HashMap[address, HashMap[address, bool]])
ownerOf: public(HashMap[uint256, address])

base_uri: String[178]

owner: public(address)
future_owner: public(address)

settler_implementation: public(address)
available_settlers: address[1024]
available_settler_count: uint256
total_settlers: public(uint256)

# token_id -> [local index][global index]
token_positions: HashMap[uint256, uint256]
totalSupply: public(uint256)
tokenOfOwnerByIndex: public(HashMap[address, uint256[MAX_INT128]])
tokenByIndex: public(uint256[MAX_INT128])


@external
def __init__(_settler_implementation: address, _base_uri: String[178]):
    self.settler_implementation = _settler_implementation
    self.base_uri = _base_uri

    self.owner = msg.sender


@view
@internal
def _get_indices(_pool: address, _from: address, _to: address) -> uint256[3]:
    # check if a pool exists in the main registry or the factory
    registry: address = AddressProvider(ADDRESS_PROVIDER).get_registry()
    if Registry(registry).get_lp_token(_pool) == 0:
        registry = AddressProvider(ADDRESS_PROVIDER).get_address(3)
    return Registry(registry).get_coin_indices(_pool, _from, _to)


@internal
def _burn(_from: address, _token_id: uint256):
    assert self.ownerOf[_token_id] == _from

    # update enumeration data
    f_last_idx: uint256 = self.balanceOf[_from] - 1

    t_pos: uint256 = self.token_positions[_token_id]
    t_local_idx: uint256 = shift(t_pos, -128)

    # replace token in from array if necessary
    if t_local_idx != f_last_idx:
        # last token id
        t_last: uint256 = self.tokenOfOwnerByIndex[_from][f_last_idx]
        # update the last token's position with it's new spot
        self.token_positions[t_last] = shift(t_local_idx, 128) + self.token_positions[t_last] % 2 ** 128
        # replace the old token with the last token
        self.tokenOfOwnerByIndex[_from][t_local_idx] = t_last
    # zero out the storage at the last token's position
    self.tokenOfOwnerByIndex[_from][f_last_idx] = 0

    # do the same globally now
    t_global_idx: uint256 = t_pos % 2 ** 128
    global_last_idx: uint256 = self.totalSupply - 1

    if t_global_idx != global_last_idx:
        t_last: uint256 = self.tokenByIndex[global_last_idx]
        self.token_positions[t_last] = self.token_positions[t_last] % 2 ** 128 + t_global_idx
        self.tokenByIndex[t_global_idx] = t_last
    self.tokenByIndex[global_last_idx] = 0

    self.totalSupply = global_last_idx
    self.balanceOf[_from] = f_last_idx
    self.ownerOf[_token_id] = ZERO_ADDRESS

    # reset approval if needed
    if self.getApproved[_token_id] != ZERO_ADDRESS:
        self.getApproved[_token_id] = ZERO_ADDRESS
        log Approval(_from, ZERO_ADDRESS, _token_id)

    log Transfer(_from, ZERO_ADDRESS, _token_id)


@internal
def _mint(_to: address, _token_id: uint256):
    assert _to != ZERO_ADDRESS  # dev: cannot mint to ZERO_ADDRESS
    assert self.ownerOf[_token_id] == ZERO_ADDRESS  # dev: already minted

    global_idx: uint256 = self.totalSupply
    local_idx: uint256 = self.balanceOf[_to]

    # add to enumeration targets
    self.token_positions[_token_id] = shift(local_idx, 128) + global_idx
    self.tokenByIndex[global_idx] = _token_id
    self.tokenOfOwnerByIndex[_to][local_idx] = _token_id

    # update local and global balances
    self.totalSupply = global_idx + 1
    self.balanceOf[_to] = local_idx + 1
    self.ownerOf[_token_id] = _to

    log Transfer(ZERO_ADDRESS, _to, _token_id)


@internal
def _transfer(_from: address, _to: address, _token_id: uint256):
    assert _to != ZERO_ADDRESS

    # reset approval if needed
    if self.getApproved[_token_id] != ZERO_ADDRESS:
        self.getApproved[_token_id] = ZERO_ADDRESS
        log Approval(_from, ZERO_ADDRESS, _token_id)

    # update enumeration data
    f_last_idx: uint256 = self.balanceOf[_from] - 1

    t_pos: uint256 = self.token_positions[_token_id]
    t_local_idx: uint256 = shift(t_pos, -128)
    t_global_idx: uint256 = t_pos % 2 ** 128

    # replace token in from array if necessary
    if t_local_idx != f_last_idx:
        # last token id
        t_last: uint256 = self.tokenOfOwnerByIndex[_from][f_last_idx]
        # update the last token's position with it's new spot
        self.token_positions[t_last] = shift(t_local_idx, 128) + self.token_positions[t_last] % 2 ** 128
        # replace the old token with the last token
        self.tokenOfOwnerByIndex[_from][t_local_idx] = t_last
    # zero out the storage at the last token's position
    self.tokenOfOwnerByIndex[_from][f_last_idx] = 0

    # add the token to recipient's array of tokens
    t_last_idx: uint256 = self.balanceOf[_to]
    self.tokenOfOwnerByIndex[_to][t_last_idx] = _token_id
    # update it's position
    self.token_positions[_token_id] = shift(t_last_idx, 128) + t_global_idx

    self.ownerOf[_token_id] = _to
    self.balanceOf[_from] = f_last_idx
    self.balanceOf[_to] = t_last_idx + 1
    log Transfer(_from, _to, _token_id)


@payable
@external
def swap_to_synth(
    _from: address,
    _to: address,
    _synth: address,
    _dx: uint256,
    _min_dy: uint256,
    _swap_data: SwapData[2],
    _receiver: address = msg.sender
) -> uint256:
    settler: address = ZERO_ADDRESS
    count: uint256 = self.available_settler_count
    if count == 0:
        settler = create_forwarder_to(self.settler_implementation)
        Settler(settler).initialize()
        log NewSettler(settler)
    else:
        count -= 1
        settler = self.available_settlers[count]
        self.available_settler_count = count

    # forward value to the settler
    if _from == ETH_ADDRESS:
        assert msg.value == _dx
    else:
        resp: Bytes[32] = raw_call(
            _from,
            _abi_encode(
                msg.sender,
                settler,
                _dx,
                method_id=method_id("transferFrom(address,address,uint256)")
            ),
            max_outsize=32,
        )
        if len(resp) != 0:
            assert convert(resp, bool)

    # perform the first stable swap
    Settler(settler).exchange(
        _swap_data[0]._pool,
        _swap_data[0]._from,
        _swap_data[0]._to,
        ZERO_ADDRESS,
        _dx,
        _swap_data[0]._i,
        _swap_data[0]._j,
        _swap_data[0]._use_underlying,
        value=msg.value,
    )
    # perform the second stable swap if neccessary
    if _swap_data[0]._pool != ZERO_ADDRESS:
        Settler(settler).exchange(
            _swap_data[1]._pool,
            _swap_data[1]._from,
            _swap_data[1]._to,
            ZERO_ADDRESS,
            _dx,
            _swap_data[1]._i,
            _swap_data[1]._j,
            _swap_data[1]._use_underlying
        )

    # convert the synth
    currency_key: bytes32 = Synth(_synth).currencyKey()
    Settler(settler).convert_synth(
        ERC20(_to).balanceOf(settler),
        Synth(_to).currencyKey(),
        currency_key,
    )
    # make sure not rekt
    assert ERC20(settler).balanceOf(_synth) >= _min_dy

    token_id: uint256 = bitwise_or(convert(currency_key, uint256), convert(settler, uint256))
    self._mint(_receiver, token_id)
    return token_id


@external
def approve(_approved: address, _token_id: uint256):
    """
    @notice Change or reaffirm the approved address for an NFT.
    @dev The zero address indicates there is no approved address.
        Throws unless `msg.sender` is the current NFT owner, or an authorized
        operator of the current owner.
    @param _approved The new approved NFT controller.
    @param _token_id The NFT to approve.
    """
    owner: address = self.ownerOf[_token_id]
    assert msg.sender == owner or self.isApprovedForAll[owner][msg.sender]  # dev: only owner or operator

    self.getApproved[_token_id] = _approved
    log Approval(owner, _approved, _token_id)


@external
def safeTransferFrom(_from: address, _to: address, _token_id: uint256, _data: Bytes[512] = b""):
    """
    @notice Transfers the ownership of an NFT from one address to another address
    @dev Throws unless `msg.sender` is the current owner, an authorized
        operator, or the approved address for this NFT. Throws if `_from` is
        not the current owner. Throws if `_to` is the zero address. Throws if
        `_token_id` is not a valid NFT. When transfer is complete, this function
        checks if `_to` is a smart contract (code size > 0). If so, it calls
        `onERC721Received` on `_to` and throws if the return value is not
        `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    @param _from The current owner of the NFT
    @param _to The new owner
    @param _token_id The NFT to transfer
    @param _data Additional data with no specified format, sent in call to `_to`
    """
    owner: address = self.ownerOf[_token_id]
    assert msg.sender in [owner, self.getApproved[_token_id]] or self.isApprovedForAll[owner][msg.sender]
    assert _from == owner

    self._transfer(_from, _to, _token_id)
    if _to.is_contract:
        # we use a shr + PUSH4 instead of a clamp + PUSH32
        resp: uint256 = ERC721Receiver(_to).onERC721Received(msg.sender, _from, _token_id, _data)
        assert shift(resp, -224) == 353073666  # 0x150b7a02


@external
def setApprovalForAll(_operator: address, _approved: bool):
    """
    @notice Enable or disable approval for a third party ("operator") to manage
        all of `msg.sender`'s assets.
    @param _operator Address to add to the set of authorized operators.
    @param _approved True if the operator is approved, false to revoke approval.
    """
    self.isApprovedForAll[msg.sender][_operator] = _approved
    log ApprovalForAll(msg.sender, _operator, _approved)


@external
def transferFrom(_from: address, _to: address, _token_id: uint256):
    """
    @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
        TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
        THEY MAY BE PERMANENTLY LOST
    @dev Throws unless `msg.sender` is the current owner, an authorized
        operator, or the approved address for this NFT. Throws if `_from` is
        not the current owner. Throws if `_to` is the zero address. Throws if
        `_token_id` is not a valid NFT.
    @param _from The current owner of the NFT
    @param _to The new owner
    @param _token_id The NFT to transfer
    """
    owner: address = self.ownerOf[_token_id]
    assert msg.sender in [owner, self.getApproved[_token_id]] or self.isApprovedForAll[owner][msg.sender]
    assert _from == owner

    self._transfer(_from, _to, _token_id)


@view
@external
def get_swap_data(
    _from: address, _to: address, _synth: address, _amount: uint256
) -> (SwapData[2], uint256):
    """
    @notice Get swap data used for making an exchange.
    @param _from The input asset, this can be a standard asset or a synth, depending on
        the purpose of the output. If making a `swap_out` call, this should be a synth.
    @param _to A token of the same asset class as `_from`. If doing a `swap_in` call
        this should be a synth, if making a `swap_out` call this should be the target
        asset (e.g. wBTC).
    @param _synth For `swap_in` calls, this should be a synth of the desired asset class.
        For other calls, this can be the ZERO_ADDRESS.
    @param _amount The input amount for the trade
    @return SwapData[2] A list of at maximum two swap datas. If empty, a swap is not possible
    @return uint256 The expected output amount of `_synth` or `_to` if `_synth` is the
        ZERO_ADDRESS.
    """
    registry_exchange: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)
    swaps: SwapData[2] = empty(SwapData[2])
    snx_exchanger: address = SNXAddressResolver(SNX_ADDRESS_RESOLVER).getAddress(EXCHANGER_KEY)

    # check if simple exchange exists
    pool_0: address = ZERO_ADDRESS
    dy_0: uint256 = 0
    pool_0, dy_0 = RegistryExchange(registry_exchange).get_best_rate(_from, _to, _amount)
    if pool_0 != ZERO_ADDRESS:
        indices: uint256[3] = self._get_indices(pool_0, _from, _to)
        swaps[0] = SwapData({
            _pool: pool_0,
            _from: _from,
            _to: _to,
            _i: indices[0],
            _j: indices[1],
            _use_underlying: indices[2],
        })
        output: uint256 = dy_0
        if _synth != ZERO_ADDRESS:
            output = SynthExchanger(snx_exchanger).getAmountsForExchange(dy_0, Synth(_to).currencyKey(), Synth(_synth).currencyKey())
        return swaps, output

    # iterate through complements and find an intersection
    # NOTE: This approach doesn't take into account intersections which
    # occur exclusively via factory pools. This is due to the fact
    # that the factory does not have the `get_coin_swap_complement` fn
    registry: address = AddressProvider(ADDRESS_PROVIDER).get_registry()
    best_complement: address = ZERO_ADDRESS
    best_pool_0: address = ZERO_ADDRESS
    best_pool_1: address = ZERO_ADDRESS
    best_dy: uint256 = 0

    break_left: bool = False
    break_right: bool = False
    for i in range(128):
        if break_left and break_right:
            break

        for coin in [_from, _to]:
            # if no more complements, continue
            if break_left and coin == _from:
                continue
            if break_right and coin == _to:
                continue

            # the set of complements for a coin has no duplicates
            complement: address = Registry(registry).get_coin_swap_complement(coin, i)
            if complement == ZERO_ADDRESS:
                if coin == _from:
                    break_left = True
                else:
                    break_right = True
                continue

            # there will be repeat calls for coins which are in both sets of
            # complements. We can prevent this by keeping track of complements
            # and not making the call on the second appearance. (Using a bloom filter perhaps?)
            pool_0, dy_0 = RegistryExchange(registry_exchange).get_best_rate(_from, complement, _amount)
            if pool_0 == ZERO_ADDRESS:
                continue
            pool_1: address = ZERO_ADDRESS
            dy_1: uint256 = 0
            pool_1, dy_1 = RegistryExchange(registry_exchange).get_best_rate(complement, _to, dy_0)
            if pool_1 == ZERO_ADDRESS:
                continue
            if dy_1 < best_dy:
                continue

            # found the best, set the appropriate values and then continue
            best_dy = dy_1
            best_pool_0 = pool_0
            best_pool_1 = pool_1
            best_complement = complement

    # return empty if we did not find anything
    if best_complement == ZERO_ADDRESS:
        return swaps, 0

    # update the swaps variable with indices info
    indices: uint256[3] = self._get_indices(best_pool_0, _from, best_complement)
    swaps[0] = SwapData({
        _pool: best_pool_0,
        _from: _from,
        _to: best_complement,
        _i: indices[0],
        _j: indices[1],
        _use_underlying: indices[2]
    })
    indices = self._get_indices(best_pool_1, best_complement, _to)
    swaps[1] = SwapData({
        _pool: best_pool_1,
        _from: best_complement,
        _to: _to,
        _i: indices[0],
        _j: indices[1],
        _use_underlying: indices[2]
    })

    output: uint256 = best_dy
    if _synth != ZERO_ADDRESS:
        output = SynthExchanger(snx_exchanger).getAmountsForExchange(best_dy, Synth(_to).currencyKey(), Synth(_synth).currencyKey())
    return swaps, output


@external
def commit_transfer_ownership(_future_owner: address):
    assert msg.sender == self.owner
    self.future_owner = _future_owner


@external
def accept_transfer_ownership():
    future_owner: address = self.future_owner
    assert msg.sender == future_owner
    self.owner = future_owner


@external
def set_base_uri(_base_uri: String[178]):
    assert msg.sender == self.owner
    self.base_uri = _base_uri


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
def tokenURI(_token_id: uint256) -> String[256]:
    # This is likely prohibitively expensive if called on-chain.
    base_uri: String[178] = self.base_uri
    assert len(base_uri) != 0
    assert self.ownerOf[_token_id] != ZERO_ADDRESS

    if _token_id == 0:
        return concat(base_uri, "0")

    buffer: Bytes[78] = b""
    digits: uint256 = 78

    for i in range(78):
        # go forward to find the # of digits, and set it
        # only if we have found the last index
        if digits == 78 and _token_id / 10 ** i == 0:
            digits = i

        value: uint256 = ((_token_id / 10 ** (77 - i)) % 10) + 48
        char: Bytes[1] = slice(convert(value, bytes32), 31, 1)
        # EIP-2929: *CALL opcodes to precompiles cost 100 gas
        buffer = raw_call(
            convert(4, address),
            concat(buffer, char),
            max_outsize=78,
            is_static_call=True
        )

    return concat(base_uri, convert(slice(buffer, 78 - digits, digits), String[78]))
