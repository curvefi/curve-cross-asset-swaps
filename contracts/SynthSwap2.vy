# @version 0.3.0
"""
@title Curve x Synthetix Cross Asset Swaps
@license MIT
@author CurveFi
"""


interface ERC721Receiver:
    def onERC721Received(_operator: address, _from: address, _token_id: uint256, _data: Bytes[512]) -> uint256: nonpayable


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
