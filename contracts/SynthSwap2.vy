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


@internal
def _transfer(_from: address, _to: address, _token_id: uint256):
    assert _to != ZERO_ADDRESS

    # reset approval if needed
    if self.getApproved[_token_id] != ZERO_ADDRESS:
        self.getApproved[_token_id] = ZERO_ADDRESS
        log Approval(_from, ZERO_ADDRESS, _token_id)

    self.ownerOf[_token_id] = _to
    self.balanceOf[_from] -= 1
    self.balanceOf[_to] += 1
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
