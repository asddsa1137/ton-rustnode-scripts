# ton-rustnode-scripts

This scripts allow to build and run Free TON Rust node on baremetal host and offers systemd installation.

Tested on Ubuntu 20.04

# Getting Started

## 1. Clone TON Labs rustnet repo

```
git clone https://github.com/tonlabs/rustnet.ton.dev.git
```

## 2. Clone this repo

## 3. Copy files

This scripts are based on rustnet repo structure and extends it. 
```
cd ton-rustnode-scripts
cp -r * ../rustnet.ton.dev/scripts/
cd ../rustnet.ton.dev/scripts/
```

## 4. Build

```
./build.sh
```

## 5. Setup

```
./setup.sh
```

## 6. Install

```
./install_systemd.sh
```

## 7. Run

```
systemctl start ton-rust-node.service
```

## 8. Validate

### Validate using msig wallet (single stake)

0. Follow instructions to setup validator node at https://docs.ton.dev/86757ecb2/p/708260-run-validator.
1. Put your msig wallet address into `/var/ton-node/configs/${HOSTNAME}.addr` file.
2. Put your msig key into `/var/ton-node/configs/keys/msig.keys.json` file.
3. Run `./validator_msig.sh ${STAKE}`. You can use cron to run this command periodically. 

### Validate using depool

0. Follow instructions to setup depool at https://docs.ton.dev/86757ecb2/p/04040b-run-depool-v3.
1. Put your msig validator wallet address into `/var/ton-node/configs/${HOSTNAME}.addr` file.
2. Put your msig key into `/var/ton-node/configs/keys/msig.keys.json` file.
3. Put your depool address into `/var/ton-node/configs/depool.addr`.
4. (Optionally!) If you want this script to perform ticktocks itself, put your configured helper contract address into `/var/ton-node/configs/helper.addr` and helper contract keys into `/var/ton-node/configs/keys/helper.json`.
5. Run `./validator_depool.sh`.

# Important locations

By default build will be performed under `rustnet.ton.dev/build` directory.
Node binary will be saved to `rustnet.ton.dev/bin` directory.
Tools like `tonos-cli` will be saved to `rustnet.ton.dev/tools`.
Working directory is `/var/ton-node`.

# Update node
```
cd rustnet.ton.dev/scripts
./build.sh
systemctl restart ton-rust-node.service
```

# Known issues

1. Scripts are leaving some trash in random directories. 
