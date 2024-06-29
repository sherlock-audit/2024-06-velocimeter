# Velocimeter

This repo contains the contracts for Velocimeter Finance, an AMM inspired by Solidly.

## Testing

This repo uses Foundry (for Solidity testing and for deployment)

Foundry Setup

```ml
forge init
forge build
forge test
```

## Deployment

This project's deployment process uses forge scripts

Deployment contains 2 steps:

1. `forge script --rpc-url http://rpc.xyz script/Deployment.s.sol` 
2. `forge script --rpc-url http://rpc.xyz script/OFlowDeployment.s.sol` 

To init the active period

1. `forge script --rpc-url http://rpc.xyz script/StartActivePeriod.s.sol` 

## Articles
https://paragraph.xyz/@velocimeter/velocimeter-v4
https://paragraph.xyz/@velocimeter/otokens


      