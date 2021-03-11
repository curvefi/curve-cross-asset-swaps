import brownie


def test_add_synth(alice, swap, sUSD, curve_susd):
    swap.add_synth(sUSD, curve_susd, {"from": alice})

    assert swap.synth_pools(sUSD) == curve_susd
    for coin in [curve_susd.coins(i) for i in range(4)]:
        assert swap.swappable_synth(coin) == sUSD


def test_already_added(alice, swap, sUSD, curve_susd):
    swap.add_synth(sUSD, curve_susd, {"from": alice})

    with brownie.reverts("dev: already added"):
        swap.add_synth(sUSD, curve_susd, {"from": alice})


def test_wrong_pool(alice, swap, sUSD, curve_sbtc):
    with brownie.reverts("dev: synth not in pool"):
        swap.add_synth(sUSD, curve_sbtc, {"from": alice})


def test_not_a_synth(alice, swap, curve_susd):
    dai = curve_susd.coins(0)
    with brownie.reverts():
        swap.add_synth(dai, curve_susd, {"from": alice})
