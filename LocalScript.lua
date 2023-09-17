--!strict

type Pair<T,S> = {first: T, second: S}


-- Vector3 pair that contains all the informations about the next point and normal the character is going to climb to
local targetPoint: Vector3? = nil
local targetNormal: Vector3? = nil

--local climbingDir: Vector3 = Vector3.one

-- boolean pair that is used to keep track of the current player status, e.g. if the player is climbing, some other
-- parts in the code get disabled so prevent "interventions"
local climbing: boolean = false
local tweening: boolean = false

local Constants = {
	PLAYER_WALL_OFFSET = 0.4,
	PLAYER_HOR_MOVE_AMT = 2,
	
	LEDGE_Y_THRESHOLD = 0.1
}

local tweenValue: CFrameValue = Instance.new("CFrameValue")


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

repeat wait() until hrp ~= nil


local Utils = {}
do
	
	function Utils.elementFromTuple(i: number, ...: any?): any?
		local t = {...}
		
		assert(i >= 1 and i <= #t, "Index ouf of tuple bounds")
		
		return t[i]
	end
	
	function Utils.createTargetCFrame()
		assert(targetPoint ~= nil, "targetPoint should have a value")
		assert(targetNormal ~= nil, "targetNormal should have a value")
		
		return CFrame.new(targetPoint) * CFrame.Angles(targetNormal.X, targetNormal.Y, targetNormal.Z)
	end
end



-- Module containing necessary math functions
local MathUtils = {}
do

	-- Convert a Vector3's components to it's radiant representation
	function MathUtils.vec3_rad(v: Vector3): Vector3
		return Vector3.new(math.rad(v.X),math.rad(v.Y),math.rad(v.Z))
	end
	
	-- Returns the point rotated around another point given the pivot, the rotation (given as a Vector3), and the offset vector
	-- (if no offset vector is used, Vector3.zero gets used by default)
	function MathUtils.rotatePointAroundPoint(p: Vector3, a: Vector3, off: Vector3?): Vector3
		return (CFrame.new(p) * CFrame.Angles(math.rad(a.X),math.rad(a.Y),math.rad(a.Z)) * CFrame.new(off or Vector3.zero)).Position
	end

	-- Same as rotatePointAroundPoint, but the angle should be passed as radians
	function MathUtils.rotatePointAroundPoint_AngleRad(p: Vector3, a: Vector3, off: Vector3?): Vector3
		return (CFrame.new(p) * CFrame.Angles(a.X,a.Y,a.Z) * CFrame.new(off or Vector3.zero)).Position
	end

	-- Same as rotatePointAroundPoint, but uses the player's HumanoidRootPart position and orientation
	function MathUtils.rotatePointAroundPlayer(off: Vector3?): Vector3
		return MathUtils.rotatePointAroundPoint(hrp.Position,hrp.Orientation,off)
	end
end



-- The general tweening information used
local TweenCreation = {}
do
	local function _infoTimeFromNumber(dur: number): TweenInfo
		return TweenInfo.new(dur,Enum.EasingStyle.Sine,Enum.EasingDirection.Out)
	end
	
	function TweenCreation.create(dur: number): Tween
		tweening = true
		
		local t: Tween = tweenService:Create(tweenValue, 
			_infoTimeFromNumber(dur), 
			{ ["Value"] = Utils.createTargetCFrame() } )
		
		t.Completed:Once(function(ps: Enum.PlaybackState)
			--task.wait(0.5)
			tweening = false
		end)
		
		return t
	end

end




local Raycasts = {}
do
	
	local cubes: {Part} = table.create(2, (function(): Part
		local out = Instance.new("Part")
		out.Anchored = true
		out.CanCollide = false
		out.BrickColor = BrickColor.random()
		out.Parent = workspace
		
		return out
	end)()
	)
	
	function Raycasts.topDownCast(off: Vector3, len: number): (Vector3, Vector3, RaycastParams)
		
		return MathUtils.rotatePointAroundPlayer(off),
			Vector3.yAxis * len,
			RaycastFilters.default
	end
	
	function Raycasts.playerDirCast(off: Vector3, len: number, y: number): (Vector3, Vector3, RaycastParams)
		
		local p: Vector3 = MathUtils.rotatePointAroundPlayer(off)
		p = Vector3.new(p.X, y, p.Z)
		
		return p,
			hrp.CFrame.LookVector * len,
			RaycastFilters.default
	end
	
	function Raycasts.playerOrthoCast(off: Vector3, len: number, y: number): (Vector3, Vector3, RaycastParams)
		
		local p: Vector3 = MathUtils.rotatePointAroundPlayer(off)
		p = Vector3.new(p.X, y, p.Z)
		
		return p,
			hrp.CFrame.RightVector * len,
			RaycastFilters.default
	end
	
	function Raycasts.visualizeRay(o: Vector3, dir: Vector3, i: number)
		
		local towards_point: Vector3 =  o + dir
		local distance: number = (o - towards_point).Magnitude
		
		cubes[i].Size = Vector3.new(0.1,0.1,distance)
		cubes[i].CFrame = CFrame.new(o, towards_point) * CFrame.new(0, 0, -distance / 2)
	end
end



-- Module containing necessary functions for the climbing checks
local ClimbingFunctions = {}
do
	
	type CheckInfo = Pair<Vector3, number>
	type RaycastFunc = (off: Vector3, len: number, y: number) -> (Vector3, Vector3, RaycastParams)
	
	local function _calc_climbXDir(): number
		return uis:IsKeyDown(Enum.KeyCode.A) and -1 or (uis:IsKeyDown(Enum.KeyCode.D) and 1 or 0 )
	end
	
	local climbDir: number = 0
	
	local function _target_fromRays(y_info: CheckInfo, xz_info: CheckInfo, ortho: boolean, player_dir_logic: RaycastFunc): (Vector3?, Vector3?)
		
		local x_off: Vector3 = Vector3.new(climbDir,1,1)
		
		local function __adjustForPlayerModel(tp: Vector3, xz_dir: Vector3): Vector3
			return (tp + xz_dir * 0.4) - Vector3.new(0,2)
		end
		
		
		local y_check: RaycastResult? = workspace:Raycast(Raycasts.topDownCast(y_info.first * x_off, y_info.second))
		
		if y_check then
			
			local xz_check: RaycastResult? = workspace:Raycast(player_dir_logic(xz_info.first * x_off, 
				xz_info.second * (ortho and climbDir or 1),
				y_check.Position.Y - Constants.LEDGE_Y_THRESHOLD))
			
			Raycasts.visualizeRay(
				MathUtils.rotatePointAroundPlayer(xz_info.first),
				hrp.CFrame.RightVector * xz_info.second,
				1
			)
			
			if xz_check then
				
				local out_tp: Vector3 = Vector3.new(xz_check.Position.X, y_check.Position.Y, xz_check.Position.Z)
				local out_tn: Vector3 = Vector3.new(0, math.atan2(xz_check.Normal.X, xz_check.Normal.Z), 0)
				
				return __adjustForPlayerModel(out_tp, xz_check.Normal), out_tn
			end
			return nil, nil
		end
		return nil, nil
	end
	
	type CheckStruct = {y: CheckInfo, xz: CheckInfo, ortho: boolean}
	
	local checkInfoLookUp: {[string]: CheckStruct} = {
		
		["init"] = {
			y = 	{ first = Vector3.new(0,7,-0.9), 	second = -6 }, 
			xz = 	{ first = Vector3.zero, 			second = 1  },
			ortho = false
		},
		
		["vertical1"] = {
			
		},
		
		["sideways1"] = {
			y = 	{ first = Vector3.new(1.9,3,0), 	second = -2 }, 
			xz = 	{ first = Vector3.zero,				second = 2.5},
			ortho = true
		},
		
		["sideways2"] = {
			y = 	{ first = Vector3.new(1.5,3,-0.7),	second = -2 }, 
			xz = 	{ first = Vector3.new(1.5,0,0),		second = 1  },
			ortho = false
		},
		
		["sideways3"] = {
			y = 	{ first = Vector3.new(0,3,-0.7), 	second = -2  }, 
			xz = 	{ first = Vector3.new(2.5,0,-0.7),	second = -2.5},
			ortho = true
		}
		
	}
	
	local function _updateClimbingStuff(key: string, tween_dur: number, extra_f: (() -> ())? ): boolean
		
		local checkInfo: CheckStruct = checkInfoLookUp[key]
		
		targetPoint, targetNormal = _target_fromRays(checkInfo.y, checkInfo.xz, checkInfo.ortho, checkInfo.ortho and Raycasts.playerOrthoCast or Raycasts.playerDirCast)
		
		if targetPoint and targetNormal then
			if extra_f then extra_f() end
			TweenCreation.create(tween_dur):Play()
			return true
		end
		
		return false
	end
	
	function ClimbingFunctions.init()
		
		_updateClimbingStuff("init", 0.33, function()
			
			tweenValue.Value = hrp.CFrame
			
			hrp.Anchored = true
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			hum.AutoRotate = false
			climbing = true
		end)
	end
	
	function ClimbingFunctions.cancel()
		if tweening then return end
		
		hrp.Anchored = false
		hum.AutoRotate = true
		climbing = false
	end
	
	function ClimbingFunctions.moveAlongLedge()
		
		climbDir = _calc_climbXDir()
		
		--_updateClimbingStuff("sideways1",0.2)
		for i=1, 3, 1 do
			if _updateClimbingStuff("sideways"..i, 0.2) then
				break
			end
		end
	end
	
	function ClimbingFunctions.moveVertically()
		
		climbDir = _calc_climbXDir()
	end
end


local KeyEvents: {[Enum.KeyCode]: () -> ()} = {
	[Enum.KeyCode.Space] = ClimbingFunctions.init,
	[Enum.KeyCode.C] = ClimbingFunctions.cancel
}

uis.InputBegan:Connect(function(inp: InputObject, gpe: boolean)
	
	local key: Enum.KeyCode = inp.KeyCode
	
	local evt: (() -> ())? = KeyEvents[key]
	if evt and not tweening then evt() end
	
end)


runService.PreSimulation:Connect(function(dt: number)
	if climbing then
		hrp.CFrame = tweenValue.Value
	end
end)

runService.PostSimulation:Connect(function(dt: number)
	
end)

runService.Heartbeat:Connect(function(dt: number)
	if climbing and not tweening then
		
		if uis:IsKeyDown(Enum.KeyCode.W) or
			uis:IsKeyDown(Enum.KeyCode.S) or
			uis:IsKeyDown(Enum.KeyCode.A) or
			uis:IsKeyDown(Enum.KeyCode.D)
		then
			ClimbingFunctions.moveAlongLedge()
		end
	end
end)
