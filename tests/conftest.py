import pytest
from brownie_tokens import MintableForkToken


# isolation


@pytest.fixture(autouse=True)
def isolation_setup(fn_isolation):
    pass


# account helpers


@pytest.fixture(scope="session")
def alice(accounts):
    yield accounts[0]


@pytest.fixture(scope="session")
def bob(accounts):
    yield accounts[1]


@pytest.fixture(scope="session")
def charlie(accounts):
    yield accounts[2]


# deployments


@pytest.fixture(scope="module")
def settler_implementation(Settler, alice):
    yield Settler.deploy({"from": alice})


@pytest.fixture(scope="module")
def swap(SynthSwap, alice, settler_implementation):
    yield SynthSwap.deploy(settler_implementation, 3, {"from": alice})


# settlers


@pytest.fixture(scope="module")
def settler_sbtc(Settler, alice, swap, DAI, sBTC, add_synths):
    amount = 1_000_000 * 10 ** 18
    DAI._mint_for_testing(alice, amount)
    DAI.approve(swap, 2 ** 256 - 1, {"from": alice})

    tx = swap.swap_into_synth(DAI, sBTC, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    yield Settler.at(hex(token_id))


@pytest.fixture(scope="module")
def settler_seth(Settler, alice, swap, DAI, sETH, add_synths):

    amount = 1_000_000 * 10 ** 18
    DAI._mint_for_testing(alice, amount)
    DAI.approve(swap, 2 ** 256 - 1, {"from": alice})

    tx = swap.swap_into_synth(DAI, sETH, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    yield Settler.at(hex(token_id))


@pytest.fixture(scope="module")
def settler_susd(Settler, alice, swap, WBTC, sUSD, add_synths):

    amount = 50 * 10 ** 8
    WBTC._mint_for_testing(alice, amount)
    WBTC.approve(swap, 2 ** 256 - 1, {"from": alice})

    tx = swap.swap_into_synth(WBTC, sUSD, amount, 0, {"from": alice})
    token_id = tx.events["Transfer"][-1]["token_id"]

    yield Settler.at(hex(token_id))


# synths


@pytest.fixture(scope="module")
def sUSD():
    yield MintableForkToken("0x57ab1ec28d129707052df4df418d58a2d46d5f51")


@pytest.fixture(scope="module")
def sBTC():
    yield MintableForkToken("0xfe18be6b3bd88a2d2a7f928d00292e7a9963cfc6")


@pytest.fixture(scope="module")
def sETH():
    yield MintableForkToken("0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb")


@pytest.fixture(scope="module")
def sEUR():
    yield MintableForkToken("0xD71eCFF9342A5Ced620049e616c5035F1dB98620")


# swappable coins


@pytest.fixture(scope="module")
def DAI():
    yield MintableForkToken("0x6B175474E89094C44Da98b954EedeAC495271d0F")


@pytest.fixture(scope="module")
def USDT():
    yield MintableForkToken("0xdAC17F958D2ee523a2206206994597C13D831ec7")


@pytest.fixture(scope="module")
def WBTC():
    yield MintableForkToken("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599")


# curve pools


@pytest.fixture(scope="module")
def curve_susd(Contract):
    yield Contract("0xA5407eAE9Ba41422680e2e00537571bcC53efBfD")


@pytest.fixture(scope="module")
def curve_sbtc(Contract):
    yield Contract("0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714")


@pytest.fixture(scope="module")
def curve_seth(Contract):
    yield Contract("0xc5424b857f758e906013f3555dad202e4bdb4567")


@pytest.fixture(scope="module")
def curve_seur(Contract):
    yield Contract("0x0Ce6a5fF5217e38315f87032CF90686C96627CAA")


# test setup


@pytest.fixture(scope="module")
def add_synths(
    alice, swap, sUSD, sBTC, sETH, sEUR, curve_susd, curve_sbtc, curve_seth, curve_seur
):
    swap.add_synth(sUSD, curve_susd, {"from": alice})
    swap.add_synth(sBTC, curve_sbtc, {"from": alice})
    swap.add_synth(sETH, curve_seth, {"from": alice})
    swap.add_synth(sEUR, curve_seur, {"from": alice})
