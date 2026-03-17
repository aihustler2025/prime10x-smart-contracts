# Prime10X Contract Addresses

## Base Sepolia

| Contract | Address | BaseScan |
| --- | --- | --- |
| BadgeSBT | `0x1fb9d377f6d73fe8d1573affaf4a342c7bf426e6` | [contract](https://sepolia.basescan.org/address/0x1fb9d377f6d73fe8d1573affaf4a342c7bf426e6) / [deploy tx](https://sepolia.basescan.org/tx/0x2dfc2943af19a16615ec59085c685d7dd67651bb74451cdba67d2811a9d3176f) |
| MarketingVault | `0x8b981488296de50289ae26b67516333d8ba216ea` | [contract](https://sepolia.basescan.org/address/0x8b981488296de50289ae26b67516333d8ba216ea) / [deploy tx](https://sepolia.basescan.org/tx/0x83494f69a912c410b5b90d499f18a60882ebaca5f55545976179190025281727) |
| RewardVoucher | `0x0cea12c59fa4704ff153e2df1282e6c7a1529880` | [contract](https://sepolia.basescan.org/address/0x0cea12c59fa4704ff153e2df1282e6c7a1529880) / [deploy tx](https://sepolia.basescan.org/tx/0xe1d3c4f63c31878af03d1f0566dcd3eba1a8ad8791fa1a3bbd1c9cd6023a2017) |

Deployer: [`0x756F6DdCB76456D563B2d1A0c303E79B1170E5b1`](https://sepolia.basescan.org/address/0x756F6DdCB76456D563B2d1A0c303E79B1170E5b1)

MarketingVault token address not yet set. Call `setTokenAddress()` after TENX deployment.

## Ownership Transfer (Base Sepolia)

`transferOwnership(0x57cb69D41aD0A413d718DcCd5f6551e4abE526e9)` called on all contracts. **Pending — new owner must call `acceptOwnership()` on each contract to finalise.**

| Contract | transferOwnership tx |
| --- | --- |
| BadgeSBT | [0xf27398...](https://sepolia.basescan.org/tx/0xf2739898ba1dc843de5b7c1d77950b1b17dafe59b0ddfd601e87bd9b774f73ea) |
| MarketingVault | [0xb4da6f...](https://sepolia.basescan.org/tx/0xb4da6f7db496c23001579d82215a6ad5c4c1905e2cb5d8184f9dd3f21a665841) |
| RewardVoucher | [0x5a7b3e...](https://sepolia.basescan.org/tx/0x5a7b3e6872a31f7991575c50c0ce7519d6923f581eff58447b2c1133ef69f5f3) |

## Base URI (BadgeSBT)

`setBaseURI("https://prime10x.io/badges/season/")` called on BadgeSBT. [tx](https://sepolia.basescan.org/tx/0x535fc587de182f9a82c4709d6ec190bd39961221550573a5347c83395c04a4e4)

## Base Mainnet

| Contract | Address | BaseScan |
| --- | --- | --- |
| BadgeSBT | `0xabe5700a843621f159569cd5dbd7129b0ab5443e` | [contract](https://basescan.org/address/0xabe5700a843621f159569cd5dbd7129b0ab5443e) / [deploy tx](https://basescan.org/tx/0x3627da958935bc5e535d8187c8ad3e79dc266697849c71cc79db69eacd00af0e) |

Deployer: [`0x756F6DdCB76456D563B2d1A0c303E79B1170E5b1`](https://basescan.org/address/0x756F6DdCB76456D563B2d1A0c303E79B1170E5b1)

| Action | Tx |
| --- | --- |
| `setMinter(0x0C71A6DF89B0c2F9fB81F3aB7825e208934b3CeC)` | [0x3ca058...](https://basescan.org/tx/0x3ca0582b6ed4f0f68dc2b10f657f75cc2986481c7be00212d878846ad0cbc3f7) |
| `transferOwnership(0x0b942103B446E068bEd29735cD8B6914eb78f8b9)` | [0xbe48b7...](https://basescan.org/tx/0xbe48b7edcc93a2989089578d1eb28b015ec8bfb4816113a44645e135dfd07ba5) |

Pending — owner must call `acceptOwnership()` to finalise.
