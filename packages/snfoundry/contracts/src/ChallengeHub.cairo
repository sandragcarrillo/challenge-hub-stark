use starknet::{ContractAddress};

#[starknet::interface]
pub trait IChallengeHub<TContractState> {
    fn create_challenge(
        ref self: TContractState,
        name: felt252,
        description: felt252,
        max_winners: u8,
        reward: u256
    ) -> u64;
    
    fn activate_challenge(ref self: TContractState, challenge_id: u64, status: bool);
    
    fn participate(ref self: TContractState, challenge_id: u64);
    
    fn select_winners(
        ref self: TContractState,
        challenge_id: u64,
        winner_address: ContractAddress
    );
    
    fn claim_reward(ref self: TContractState, challenge_id: u64);
}


#[starknet::contract]
pub mod ChallengeHub {
    use starknet::storage::Map;
    use starknet::{ContractAddress, contract_address_const};
    use starknet::{get_caller_address};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    const ETH_CONTRACT_ADDRESS: felt252 =
        0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;


    #[derive(Drop, starknet::Store)]
    struct Challenge {
        owner: ContractAddress,
        name: felt252,
        description: felt252,
        max_winners: u8,
        reward: u256,
        active: bool,
    }

    #[storage]
    struct Storage {
        challenges: Map<u64, Challenge>,
        challenge_counter: u64,
        participants: Map<(u64, ContractAddress), bool>,
        winners: Map<(u64, ContractAddress), bool>,
        winners_count: Map<u64, u8>,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ChallengeCreated: ChallengeCreated,
        ParticipantJoined: ParticipantJoined,
        WinnerSelected: WinnerSelected,
        RewardClaimed: RewardClaimed,
    }

    #[derive(Drop, starknet::Event)]
    struct ChallengeCreated {
        #[key]
        challenge_id: u64,
        owner: ContractAddress,
        reward: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ParticipantJoined {
        #[key]
        challenge_id: u64,
        participant: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct WinnerSelected {
        #[key]
        challenge_id: u64,
        winner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RewardClaimed {
        #[key]
        challenge_id: u64,
        winner: ContractAddress,
        amount: u256,
    }

 
    #[abi(embed_v0)]
    impl ChallengeHubImpl of super::IChallengeHub<ContractState> {
        fn create_challenge(
            ref self: ContractState,
            name: felt252,
            description: felt252,
            max_winners: u8,
            reward: u256
        ) -> u64 {
            let challenge_id = self.challenge_counter.read();
            let owner = get_caller_address();

            self.challenges.write(
                challenge_id,
                Challenge {
                    owner,
                    name,
                    description,
                    max_winners,
                    reward,
                    active: true,
                }
            );

            self.challenge_counter.write(challenge_id + 1);
            self.emit(Event::ChallengeCreated(ChallengeCreated { challenge_id, owner, reward }));
            challenge_id
        }

        fn activate_challenge(ref self: ContractState, challenge_id: u64, status: bool) {
            let caller = get_caller_address();
            let mut challenge = self.challenges.read(challenge_id);
            assert(challenge.owner == caller, 'Caller is not the owner');
            challenge.active = status;
            self.challenges.write(challenge_id, challenge);
        }

        fn participate(ref self: ContractState, challenge_id: u64) {
            let caller = get_caller_address();
            let challenge = self.challenges.read(challenge_id);
            assert(challenge.active, 'Challenge is not active');
            
            let is_participant = self.participants.read((challenge_id, caller));
            assert(!is_participant, 'Already participated');
            
            self.participants.write((challenge_id, caller), true);
            self.emit(Event::ParticipantJoined(ParticipantJoined { challenge_id, participant: caller }));
        }

        fn select_winners(
            ref self: ContractState,
            challenge_id: u64,
            winner_address: ContractAddress,
        ) {
            let caller = get_caller_address();
            let challenge = self.challenges.read(challenge_id);
            assert(challenge.owner == caller, 'Caller is not the owner');
            
            let current_winners = self.winners_count.read(challenge_id);
            assert(current_winners < challenge.max_winners, 'Max winners reached');
    
            self.winners.write((challenge_id, winner_address), true);
            self.winners_count.write(challenge_id, current_winners + 1);
            
            self.emit(Event::WinnerSelected(WinnerSelected { 
                challenge_id, 
                winner: winner_address 
            }));
        }

        fn claim_reward(ref self: ContractState, challenge_id: u64) {
            let caller = get_caller_address();
            let challenge = self.challenges.read(challenge_id);
            let is_winner = self.winners.read((challenge_id, caller));
            assert(is_winner, 'Not a winner');

            let winners_count: u256 = self.winners_count.read(challenge_id).into();
            let reward_per_winner = challenge.reward / winners_count;

            let token = IERC20Dispatcher { contract_address: contract_address_const::<ETH_CONTRACT_ADDRESS>() };
            token.transfer(caller, reward_per_winner);

            self.emit(Event::RewardClaimed(RewardClaimed { 
                challenge_id, 
                winner: caller, 
                amount: reward_per_winner 
            }));
        }
    }
}
