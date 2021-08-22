# ton-rustnode-scripts

This scripts allow to build and run Free TON Rust node on baremetal host and offers systemd installation.

Tested on Ubuntu 20.04

## Warning. Follow Getting Started guide, do NOT use validator_depool_v2.sh. It is EXPEREMENTAL, undocumented and does not claim to be able to work.

# Getting Started

## 0. Clone TON Labs rustnet repo

```
git clone https://github.com/tonlabs/rustnet.ton.dev.git
```

## 1. Initialize environment. 

```
. ./rustnet.ton.dev/scripts/env.sh
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
*In case on network wipe just re-run setup script.* 

## 6. Install

```
./install_systemd.sh
```

## 7. Run

```
systemctl start ton-rust-node.service
```

## Wait for node sync

First of all check service status with `systemctl status ton-rust-node.service` and node logs at `/var/ton-node/logs/output.log`. If everything up and running, sit back and relax.

You can check sync status with
```
./check_node_sync_status.sh
```
If service is up and running but you receive `connection refused` error, wait a bit more. Node does not opens console port during boot. 
If you see `timediff` less then several seconds, your node had successfully synced. 

## 8. Validate

### Validate using msig wallet (single stake)

0. Follow instructions to setup validator node at https://docs.ton.dev/86757ecb2/p/708260-run-validator.
1. Put your msig wallet address into `/var/ton-node/configs/keys/${HOSTNAME}.addr` file.
2. Put your msig key into `/var/ton-node/configs/keys/msig.keys.json` file.
3. Run `./validator_msig.sh ${STAKE}`. You can use cron to run this command periodically. 

### Validate using depool

0. Follow instructions to setup depool at https://docs.ton.dev/86757ecb2/p/04040b-run-depool-v3.
1. Put your msig validator wallet address into `/var/ton-node/configs/keys/${HOSTNAME}.addr` file.
2. Put your msig key into `/var/ton-node/configs/keys/msig.keys.json` file.
3. Put your depool address into `/var/ton-node/configs/keys/depool.addr`.
4. (Optionally!) If you want this script to perform ticktocks itself, put your configured helper contract address into `/var/ton-node/configs/keys/helper.addr` and helper contract keys into `/var/ton-node/configs/keys/helper.json`.
5. Run `./validator_depool.sh`.

# Important locations

By default build will be performed under `rustnet.ton.dev/build` directory.
Node binary will be saved to `rustnet.ton.dev/bin` directory.
Tools like `tonos-cli` will be saved to `rustnet.ton.dev/tools`.
Working directory is `/var/ton-node`.
Keys are stored at $HOME/keys and also created as a symlink at /var/ton-node/config/keys

# Update node
```
cd rustnet.ton.dev/scripts
./build.sh
systemctl restart ton-rust-node.service
```
