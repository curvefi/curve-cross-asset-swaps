# @version 0.3.0
"""
@title Curve x Synthetix Cross Asset Swaps
@license MIT
@author CurveFi
"""


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


# swap data used when performing an exchange
struct SwapData:
    _pool: address
    _i: uint256
    _j: uint256
    _use_underlying: bool


ADDRESS_PROVIDER: constant(address) = 0x0000000022D53366457F9d5E68Ec105046FC4383
SNX_ADDRESS_RESOLVER: constant(address) = 0x4E3b31eB0E5CB73641EE1E65E7dCEFe520bA3ef2
# "0x" + b"Exchanger".hex() + "00" * 23
EXCHANGER_KEY: constant(bytes32) = 0x45786368616e6765720000000000000000000000000000000000000000000000


balanceOf: public(HashMap[address, uint256])
getApproved: public(HashMap[uint256, address])
isApprovedForAll: public(HashMap[address, HashMap[address, bool]])
ownerOf: public(HashMap[uint256, address])

base_uri: String[178]

owner: public(address)
future_owner: public(address)

# token_id -> [local index][global index]
token_positions: HashMap[uint256, uint256]
totalSupply: public(uint256)
tokenOfOwnerByIndex: public(HashMap[address, uint256[MAX_INT128]])
tokenByIndex: public(uint256[MAX_INT128])


@external
def __init__(_base_uri: String[178]):
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
def get_swap_in_data(
    _from: address, _synth_a: address, _synth_b: address, _amount: uint256
) -> (SwapData[2], uint256):
    """
    @notice Get swap data used for making the swap_in exchange.
    @param _from The input asset (e.g. USDC/DAI/USDT)
    @param _synth_a A synth of the same asset class as `_from` (e.g. sUSD)
    @param _synth_b The output synth in the desired asset class (e.g. sBTC)
    @param _amount The input amount for the trade
    @return SwapData[2] A list of at maximum two swap datas. If empty a swap is not possible
    @return uint256 The expected output amount of `_synth_b`
    """
    assert _synth_a != _synth_b  # dev: no synth swap required
    registry_exchange: address = AddressProvider(ADDRESS_PROVIDER).get_address(2)
    swaps: SwapData[2] = empty(SwapData[2])
    snx_exchanger: address = SNXAddressResolver(SNX_ADDRESS_RESOLVER).getAddress(EXCHANGER_KEY)

    # check if simple exchange exists
    pool_0: address = ZERO_ADDRESS
    dy_0: uint256 = 0
    pool_0, dy_0 = RegistryExchange(registry_exchange).get_best_rate(_from, _synth_a, _amount)
    if pool_0 != ZERO_ADDRESS:
        indices: uint256[3] = self._get_indices(pool_0, _from, _synth_a)
        swaps[0] = SwapData({
            _pool: pool_0,
            _i: indices[0],
            _j: indices[1],
            _use_underlying: convert(indices[2], bool),
        })
        output: uint256 = SynthExchanger(snx_exchanger).getAmountsForExchange(dy_0, Synth(_synth_a).currencyKey(), Synth(_synth_b).currencyKey())
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

        for coin in [_from, _synth_a]:
            # if no more complements, continue
            if break_left and coin == _from:
                continue
            if break_right and coin == _synth_a:
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
            pool_1, dy_1 = RegistryExchange(registry_exchange).get_best_rate(complement, _synth_a, dy_0)
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
        _i: indices[0],
        _j: indices[1],
        _use_underlying: convert(indices[2], bool)
    })
    indices = self._get_indices(best_pool_1, best_complement, _synth_a)
    swaps[1] = SwapData({
        _pool: best_pool_1,
        _i: indices[0],
        _j: indices[1],
        _use_underlying: convert(indices[2], bool)
    })

    output: uint256 = SynthExchanger(snx_exchanger).getAmountsForExchange(best_dy, Synth(_synth_a).currencyKey(), Synth(_synth_b).currencyKey())
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
