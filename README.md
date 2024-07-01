
# Velocimeter contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
First on IOTA EVM, but code was build with any EVM-compatible network in mind. There is no plan to deploy in on Ethereum mainnet
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Users can create the liquidity pools for any of the ERC20 tokens in permissionless way.
Our internal router is not supporting fee on transfer tokens. Swap on that type of tokens needs to be done by external aggregators.

Tokens that are used for rewards/bribes that are not part of the pool needs to be whitelisted by protocol.

Any users can create gauge for pools with whitelisted tokens on one side. (Permissionless gauge creation) Otherwise, gauge for pools without whitelisted tokens can only be created by protocol.

Specific contract requirements
Option Token contract
Standard ERC20 - 18 decimal tokens are only allowed ( rebase, fee on transfer and not 18 decimals tokens are not supported) 
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
No
Example deployment script with the default start settings is available in our repository in script folder. 
It is used as a template for our deployments.
It has two parts - first Deployment.s.sol script needs to be run then OFlowDeployment.s.sol script.
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
We are not integrating with other external protocols 
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
All permissioned functions after deployment and init are going to be assigned to project msig.
Any change of the settings is reviewed by all core team members.
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
No
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, arbitrage bots, etc.)?
Function distribute on voter contract needs to be called every epoch ( one week), it can be called by anybody but team have keepers setup that call it as well.
___

### Q: Are there any hardcoded values that you intend to change before (some) deployments?
Bellow constants are adjusted before deployments to different chains

VotingEscrow
Name of the veNFT token
string constant public name = "veIVM";
string constant public symbol = "veIVM";

Max lock time
uint internal constant MAXTIME = 90 * 86400;
int128 internal constant iMAXTIME = 90 * 86400;

___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
Not applicable
___

### Q: Should potential issues, like broken assumptions about function behavior, be reported if they could pose risks in future integrations, even if they might not be an issue in the context of the scope? If yes, can you elaborate on properties/invariants that should hold?
No
___

### Q: Please discuss any design choices you made.
We make decision that we are not going to deploy to the eth mainnet.  Because of that we do not focus on the gas optimalisations, for example readability and less complexity of the code was chosen above of any gas savings techniques. 

Rewards for veNFT holders are based on the state from previous epoch snapshot that is known and that is design decision. (veNFT needs to be hold full epoch to be eligible for rewards)
For example rewards on epoch 2 flip are going to veNFT holders based on the state from epoch 1 to 2 flip

OptionTokenV4 contract by design supports only standard ERC20 - 18 decimal tokens as underlyingToken\paymentToken  ( rebase, fee on transfer and not 18 decimals tokens are not supported) 




___

### Q: Please list any known issues and explicitly state the acceptable risks for each known issue.
Any issues created by front running the distribute function on voter after epoch flip  ( doing actions on the protocol after epoch flip but before the distribute call was executed ) are acceptable risk unless it's high severity

Any issues related to variable blk in the Point structure (VotingEscrow) are acceptable risk unless it's high severity

Any issues related to views balanceOfAtNFT,totalSupplyAt  (VotingEscrow) are acceptable risk

___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
No
___

### Q: Please list any relevant protocol resources.
Bellow articles are describing the biggest changes of V4 version of the protocol 
https://paragraph.xyz/@velocimeter/velocimeter-v4
https://paragraph.xyz/@velocimeter/otokens
___

### Q: Additional audit information.
Project started as fork of https://github.com/velodrome-finance/v1
Then we build version 3 on top of above code, and then version 4 with the biggest changes on top of that.
Structure of the files/folders is not changed from the fork so you can generated the diff from that repo.
For some of the contracts new version in our repo are marked as v3,v4 etc. Only latest version of it are in scope for audit.
Contracts that are not in fork was built by our team from scratch.
___



# Audit scope


[v4-contracts @ ceaf8e4345e42440d5ca3cf7c772ca85c44b8a0e](https://github.com/Velocimeter/v4-contracts/tree/ceaf8e4345e42440d5ca3cf7c772ca85c44b8a0e)
- [v4-contracts/contracts/Flow.sol](v4-contracts/contracts/Flow.sol)
- [v4-contracts/contracts/Gauge.sol](v4-contracts/contracts/Gauge.sol)
- [v4-contracts/contracts/GaugePlugin.sol](v4-contracts/contracts/GaugePlugin.sol)
- [v4-contracts/contracts/GaugeV4.sol](v4-contracts/contracts/GaugeV4.sol)
- [v4-contracts/contracts/Minter.sol](v4-contracts/contracts/Minter.sol)
- [v4-contracts/contracts/OptionTokenV4.sol](v4-contracts/contracts/OptionTokenV4.sol)
- [v4-contracts/contracts/Pair.sol](v4-contracts/contracts/Pair.sol)
- [v4-contracts/contracts/ProxyGauge.sol](v4-contracts/contracts/ProxyGauge.sol)
- [v4-contracts/contracts/RewardsDistributorV2.sol](v4-contracts/contracts/RewardsDistributorV2.sol)
- [v4-contracts/contracts/Voter.sol](v4-contracts/contracts/Voter.sol)
- [v4-contracts/contracts/VotingEscrow.sol](v4-contracts/contracts/VotingEscrow.sol)
- [v4-contracts/contracts/factories/GaugeFactoryV4.sol](v4-contracts/contracts/factories/GaugeFactoryV4.sol)
- [v4-contracts/contracts/factories/ProxyGaugeFactory.sol](v4-contracts/contracts/factories/ProxyGaugeFactory.sol)
- [v4-contracts/contracts/interfaces/IVotingEscrow.sol](v4-contracts/contracts/interfaces/IVotingEscrow.sol)


