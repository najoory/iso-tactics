extends SceneTree

var CampaignState

func _init():
	CampaignState = load("res://scripts/campaign_state.gd").new()
	print("--- Starting CampaignState Unit Tests ---")
	test_stage_progression()
	test_retreat_logic()
	test_siege_reinforcement_tracking()
	print("--- All CampaignState Tests Passed ---")
	quit()

func test_stage_progression():
	print("Testing: Stage Progression")
	var initial_stage = CampaignState.current_stage
	CampaignState.current_stage += 1
	assert(CampaignState.current_stage == initial_stage + 1, "Stage did not increment correctly")
	print("  - Passed")

func test_retreat_logic():
	print("Testing: Retreat Logic")
	CampaignState.current_stage = 5
	CampaignState.retreat()
	assert(CampaignState.current_stage == 4, "Retreat should decrement stage")
	
	CampaignState.current_stage = 1
	CampaignState.retreat()
	assert(CampaignState.current_stage == 1, "Retreat should not go below stage 1")
	print("  - Passed")

func test_siege_reinforcement_tracking():
	print("Testing: Siege Reinforcement Tracking")
	CampaignState.last_siege_reinforcement_stage = 0
	CampaignState.current_stage = 5
	
	# Simulate trigger logic
	if CampaignState.current_stage > CampaignState.last_siege_reinforcement_stage:
		CampaignState.last_siege_reinforcement_stage = CampaignState.current_stage
	
	assert(CampaignState.last_siege_reinforcement_stage == 5, "Reinforcement stage not tracked correctly")
	
	# Simulate re-entry
	var should_grant = CampaignState.current_stage > CampaignState.last_siege_reinforcement_stage
	assert(not should_grant, "Should not grant reinforcements again for the same stage")
	print("  - Passed")
