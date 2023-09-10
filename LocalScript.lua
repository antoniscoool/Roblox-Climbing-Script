--!strict

-- Type definitions for the functions that return the tuples
type RaycastInfoFunc = (...any?) -> (Vector3, Vector3, RaycastParams)
type SpherecastInfoFunc = (RaycastParams?) -> (Vector3, number, Vector3, RaycastParams)

-- Vector3 pair that contains all the informations about the next point and normal the character is going to climb to
local targetPoint: Vector3?
local targetNormal: Vector3?

-- boolean pair that is used to keep track of the current player status, e.g. if the player is climbing, some other
-- parts in the code get disabled so prevent "interventions"
local climbing: boolean = false
local tweening: boolean = false

-- Shorthand writing for the different raycast parameters. Created because all the parameters follow pretty much the
-- same principle (their filter type is set to "include")
local function createRaycastParam(...: Instance): RaycastParams
	local r = RaycastParams.new()
	r.FilterType = Enum.RaycastFilterType.Include
	r.FilterDescendantsInstances = {...}
	return r
end

-- ...and the corresponding map containing all the necessary raycast parameters
local RaycastFilters = {
	default = createRaycastParam(workspace.Ledges),
	onlyBig = createRaycastParam(workspace.Ledges.LedgesBig),
	onlySmall = createRaycastParam(workspace.Ledges.LedgesSmall)
}

-- Local module that may or may not contain useful general purpose utility functions
local Utils = {}
do
	function Utils.fast_assert(f: () -> boolean, msg: string)
		if not f() then
			error(msg, 2)
		end
	end
end

-- All the services needed
local uis: UserInputService = game:GetService("UserInputService")
local runService: RunService = game:GetService("RunService")
local tweenService: TweenService = game:GetService("TweenService") 

-- All the components of the player needed
local char: Model?
local hrp: Part
local hum: Humanoid

-- Gets the player and it's components. It even (or should) reassign the values after the player's death
-- (components like the character model get set to nil automatically after the player's death for some reason)
local player: Player = game:GetService("Players").LocalPlayer
player.CharacterAdded:Connect(function(c: Model) 
	char = c
	hrp = (char and char:WaitForChild("HumanoidRootPart")) :: Part
	hum = (char and char:WaitForChild("Humanoid")) :: Humanoid
end)

-- The general tweening information used
local tweeninfo: TweenInfo = TweenInfo.new(0.3,Enum.EasingStyle.Sine,Enum.EasingDirection.Out)

-- Module containing necessary math functions
local MathUtils = {}
do
	
	-- Convert a Vector3's components to it's radiant representation
	function MathUtils.vec3_rad(v: Vector3): Vector3
		return Vector3.new(math.rad(v.X),math.rad(v.Y),math.rad(v.Z))
	end
	
	-- Returns the point rotated around another point given the pivot, the rotation (given as a Vector3), and the offset vector
	-- (if no offset vector is used, Vector3.zero gets used by default)
	function MathUtils.rotatePointAroundPoint(p: Vector3, a: Vector3, off: Vector3?): CFrame
		return CFrame.new(p) * CFrame.Angles(math.rad(a.X),math.rad(a.Y),math.rad(a.Z)) * CFrame.new(off or Vector3.zero)
	end
	
	-- Same as rotatePointAroundPoint, but the angle should be passed as radians
	function MathUtils.rotatePointAroundPoint_AngleRad(p: Vector3, a: Vector3, off: Vector3?): CFrame
		return CFrame.new(p) * CFrame.Angles(a.X,a.Y,a.Z) * CFrame.new(off or Vector3.zero)
	end
	
	-- Same as rotatePointAroundPoint, but uses the player's HumanoidRootPart position and orientation
	function MathUtils.rotatePointAroundPlayer(off: Vector3?): CFrame
		return MathUtils.rotatePointAroundPoint(hrp.Position,hrp.Orientation,off)
	end
end

-- Module containing necessary parameters for the raycasts
local RayChecks = {}
do
	
	-- Produces ray paramaters based on the player's HumanoidRootPart position and LookVector
	-- (used to retrieve the targetPoint's x and z components as well as the targetNormal)
	function RayChecks.player_front_cast(y: number, z_off: number?, x_off: number): (Vector3, Vector3, RaycastParams)
		local or_pos = MathUtils.rotatePointAroundPlayer(Vector3.new(x_off or 0,0, z_off or 0)).Position
		or_pos = Vector3.new(or_pos.X, y, or_pos.Z)
		return or_pos, hrp.CFrame.LookVector, RaycastFilters.default
	end
	
	-- Produces ray paramaters from top to bottom based on the player's HumanoidRootPart LookVector
	-- (used to retrieve the targetPoint's y component)
	function RayChecks.player_top_down_cast(check_fac: number, y: number?): (Vector3, Vector3, RaycastParams)
		return MathUtils.rotatePointAroundPlayer(Vector3.new(1.5 * check_fac, y or 2, -1)).Position, -Vector3.yAxis * 3, RaycastFilters.default
	end
	
	-- Same as player_front_cast, but the ray's direction is orthogonal to the player's LookVector
	function RayChecks.player_sideways_cast(check_fac: number): (Vector3, Vector3, RaycastParams)
		return MathUtils.rotatePointAroundPlayer(Vector3.new(1.5 * check_fac, 2.5, -1)).Position, hrp.CFrame.LookVector:Cross(Vector3.yAxis), RaycastFilters.default
	end
end

-- Module containing necessary parameters for the spherecasts
-- (not used yet)
local SphereChecks = {}
do
end

-- Function to create the tween that will tween the player's HRP towards the given target info
function createPlayerTween(): Tween
	tweening = true
	local r: Tween = tweenService:Create(hrp, tweeninfo, {
		["CFrame"] = CFrame.new(targetPoint :: Vector3) * CFrame.Angles(targetNormal.X, targetNormal.Y, targetNormal.Z)}
	)
	r.Completed:Once(function()
		tweening = false
	end)

	return r
end

-- Module containing necessary functions for the climbing checks
local ClimbingFunctions = {}
do
	
	-- General function to create the targetinfo for the default raycast parameter
	local function targetInfo_ForDefault(x_off: number, y_fac: number, y_off: number, z_off: number): (Vector3?, Vector3?)
		
		-- first the y check
		local y_check: RaycastResult? = rayCast(RayChecks.player_top_down_cast, y_fac, y_off)
		if y_check then
			
			-- then the x and z check
			local xz_check: RaycastResult? = rayCast(RayChecks.player_front_cast, y_check.Position.Y - 0.1, z_off, x_off)
			if xz_check then
				
				-- the final targetPoint is composed of the y_check y position and the xz_check x and z position
				local out_tp: Vector3 = Vector3.new(xz_check.Position.X, y_check.Position.Y, xz_check.Position.Z)
				
				-- the targetPoint gets adjusted to fit the player model visually
				-- the targetNormal is nothing more but the arctan of the xz_check's normal's x and z components, set as the y component for the final
				-- 		Vector3
				return (out_tp - hrp.CFrame.LookVector * 0.3) - Vector3.yAxis * 2, Vector3.new(0,math.atan2(xz_check.Normal.X,xz_check.Normal.Z),0)
			end
			
			return nil, nil
		end
		return nil, nil
	end
	
	-- Function to initiate the climbing
	function ClimbingFunctions.init()
		
		targetPoint, targetNormal = targetInfo_ForDefault(0,0,7,0)	
	
		if targetPoint and targetNormal then
			hrp.Anchored = true
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			climbing = true
			createPlayerTween():Play()
		end
	end
	
	-- Function to end the climbing
	function ClimbingFunctions.cancel()
		hrp.Anchored = false
		climbing = false
	end
	
	-- Function to keep track for the ledge's needed information while climbing
	function ClimbingFunctions.moveAlongLedge(y_fac: number)
		targetPoint, targetNormal = targetInfo_ForDefault(1.5 * y_fac, y_fac, 2.5, 0.5)
		
		if targetPoint and targetNormal then
			createPlayerTween():Play()
		end
	end
end

-- Map that stores key events that are used later in uis:InputBegan
local KeyEvents: {[Enum.KeyCode]: () -> ()} = {
	[Enum.KeyCode.Space] = function()
		ClimbingFunctions.init()
	end,
	
	[Enum.KeyCode.C] = function()
		ClimbingFunctions.cancel()
	end
}

-- Map that stores key events that are used later for real-time purposes in the runService.RenderStepped event
local KeyEventsOnUpdate: {[Enum.KeyCode]: () -> ()} = {
	[Enum.KeyCode.A] = function()
		ClimbingFunctions.moveAlongLedge(-1)
	end,

	[Enum.KeyCode.D] = function()
		ClimbingFunctions.moveAlongLedge(1)
	end
}

-- Function used to finally do the actual raycasting
function rayCast(tuple: RaycastInfoFunc, ...: any?): RaycastResult?
	return workspace:Raycast(tuple(...))
end

-- Function used to finally do the actual spherecasting (not used yet)
function sphereCast(tuple: SpherecastInfoFunc, ...: any?): RaycastResult?
	return workspace:Spherecast(tuple(...))
end


uis.InputBegan:Connect(function(inp: InputObject, gpe: boolean)
	local key: Enum.KeyCode = inp.KeyCode
	
	if key == Enum.KeyCode.Unknown then return end
	
	local key_f: (() -> ())? = KeyEvents[key]
	if key_f and not tweening then key_f() return end
end)


runService.RenderStepped:Connect(function(dt: number)
	for key, value in pairs(KeyEventsOnUpdate) do
		if uis:IsKeyDown(key) and not tweening then
			value()
			break
		end
	end
end)
