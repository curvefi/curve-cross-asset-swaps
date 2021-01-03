from brownie import SynthSwap, Settler, accounts


# set the deployer here prior to running on mainnet
DEPLOYER = accounts.add()

# token, pool
SYNTHS = [
    ("0x57ab1ec28d129707052df4df418d58a2d46d5f51", "0xA5407eAE9Ba41422680e2e00537571bcC53efBfD"),  # sUSD
    ("0xfe18be6b3bd88a2d2a7f928d00292e7a9963cfc6", "0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714"),  # sBTC
    ("0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb", "0xc5424b857f758e906013f3555dad202e4bdb4567"),  # sETH
    ("0xD71eCFF9342A5Ced620049e616c5035F1dB98620", "0x0Ce6a5fF5217e38315f87032CF90686C96627CAA"),  # sEUR
]


def main(deployer=DEPLOYER):
    settler = Settler.deploy({'from': deployer})
    swap = SynthSwap.deploy(settler, {'from': deployer})

    for token, pool in SYNTHS:
        swap.add_synth(token, pool, {'from': deployer})
