
def test_erc165_support(swap):
    erc165_interface_id = "0x01ffc9a7"
    assert swap.supportsInterface(erc165_interface_id) is True


def test_erc721_support(swap):
    erc721_interface_id = "0x80ac58cd"
    assert swap.supportsInterface(erc721_interface_id) is True
