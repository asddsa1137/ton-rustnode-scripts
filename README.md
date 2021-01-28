# ton-rustnode-scripts

This scripts allow to build and run Free TON Rust node on baremetal host and offers systemd installation.

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

# Important locations

By default build will be performed under `rustnet.ton.dev/build` directory.
Node binary will be saved to `rustnet.ton.dev/bin` directory.
Tools like `tonos-cli` will be saved to `rustnet.ton.dev/tools`.
Working directory is `/var/ton-node`.

# Known issues

1. Validator scripts are currently unsupported. 

2. Scripts are leaving some trash in random directories. 
