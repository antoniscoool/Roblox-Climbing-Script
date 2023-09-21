--!strict

type Pair<T,S> = {first: T, second: S}


local targetPoint: Vector3? = nil
local targetNormal: Vector3? = nil


local climbing: boolean = false
local tweening: boolean = false

local tween_accumulatedPos: Vector3 = Vector3.zero

local Constants = {
	NAN = 0 / 0,
	
	PLAYER_WALL_OFFSET = 0.4,
	PLAYER_HOR_MOVE_AMT = 2,
	
	SPHERECAST_DEFAULT_RADIUS = 1,
	
	LEDGE_Y_THRESHOLD = 0.1
}




local tweenValue: CFrameValue = Instance.new("CFrameValue")



local function createRaycastParam(...: Instance): RaycastParams
	local r = RaycastParams.new()
	r.FilterType = Enum.RaycastFilterType.Include
	r.FilterDescendantsInstances = {...}
	return r
end

local RaycastFilters = {
	default = createRaycastParam(workspace.Ledges),
	onlyBig = createRaycastParam(workspace.Ledges.LedgesBig),
	onlySmall = createRaycastParam(workspace.Ledges.LedgesSmall)
}




local uis: UserInputService = game:GetService("UserInputService")
local runService: RunService = game:GetService("RunService")
local tweenService: TweenService = game:GetService("TweenService") 




local char: Model?
local hrp: Part
local hum: Humanoid




local handle: Part = Instance.new("Part", workspace)
handle.Name = "sex"
handle.CanCollide = false
handle.Size = Vector3.one
handle.Transparency = 1

local player_pos: Part = Instance.new("Part", workspace)
player_pos.Name = "player_pos_templ"
player_pos.CanCollide = false
player_pos.Size = Vector3.one

local weld: Weld = Instance.new("Weld", handle)
weld.Name = "handle"
weld.Part1 = handle

local weld2: Weld = Instance.new("Weld", handle)
weld2.Name = "player_handle"
weld2.Part0 = handle
weld2.Part1 = player_pos
weld2.Enabled = false



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



local Test = {}
do
	
	function Test.setWeldedPartCFrameAndPart1()
		
		assert(weld.Part1 and weld.Part0)
		
		weld.C0 = weld.Part0.CFrame:ToObjectSpace( Utils.createTargetCFrame() )
	end
	
end


-- Module containing necessary math functions
local MathUtils = {}
do
	function MathUtils.angleBetween(v1: Vector3, v2: Vector3): number
		return math.acos(math.clamp(v1.Unit:Dot(v2.Unit), -1, 1))
	end
	
	function MathUtils.vec3_rad(v: Vector3): Vector3
		return Vector3.new(math.rad(v.X),math.rad(v.Y),math.rad(v.Z))
	end
	
	
	
	function MathUtils.rotatePointAroundPoint(p: Vector3, a: Vector3, off: Vector3?): Vector3
		return (CFrame.new(p) * CFrame.Angles(math.rad(a.X),math.rad(a.Y),math.rad(a.Z)) * CFrame.new(off or Vector3.zero)).Position
	end
	
	function MathUtils.rotatePointAroundPoint_AngleRad(p: Vector3, a: Vector3, off: Vector3?): Vector3
		return (CFrame.new(p) * CFrame.Angles(a.X,a.Y,a.Z) * CFrame.new(off or Vector3.zero)).Position
	end

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
		
		t.Completed:Once(function()
			tweening = false
		end)
		
		return t
	end
	
	function TweenCreation.createForHandle(dur: number): Tween
		tweening = true
		
		local t: Tween = tweenService:Create(handle:FindFirstChild("player_handle"),
			_infoTimeFromNumber(dur),
			{ ["C0"] = CFrame.identity }
		)
		t.Completed:Once(function()
			tweening = false
		end)
		
		return t
	end

end




local Raycasts = {}
do
	
	local cubes: {Part} = table.create(2, (function(): Part
			local out = Instance.new("Part", workspace)
			out.Anchored = true
			out.CanCollide = false
			out.BrickColor = BrickColor.random()
			
			return out
		end)()
	)
	
	function Raycasts.topDownCast(off: Vector3, len: number, y: number): (Vector3, Vector3, RaycastParams)
		
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
type RaycastsModule = typeof(Raycasts)




local Spherecasts = {}
do
	function Spherecasts.topDownCast(off: Vector3, len: number): (Vector3, number, Vector3, RaycastParams)
		return MathUtils.rotatePointAroundPlayer(off),
			Constants.SPHERECAST_DEFAULT_RADIUS,
			Vector3.yAxis * len,
			RaycastFilters.default
	end
end
type SpherecastsModule = typeof(Spherecasts)



-- Module containing necessary functions for the climbing checks
local ClimbingFunctions = {}
do
	
	type CheckInfo = Pair<Vector3, number>
	type CheckStruct = {y: CheckInfo, xz: CheckInfo, ortho: boolean}
	
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
		
		local y_check: RaycastResult? = workspace:Raycast(Raycasts.topDownCast(y_info.first * x_off, y_info.second, Constants.NAN))
		
		if y_check then
			
			local xz_check: RaycastResult? = workspace:Raycast(player_dir_logic(xz_info.first * x_off,
				xz_info.second * (ortho and climbDir or 1),
				y_check.Position.Y - Constants.LEDGE_Y_THRESHOLD))
			
			if xz_check then
				
				local old_tp = targetPoint or hrp.Position
				local old_tn = targetNormal or MathUtils.vec3_rad(hrp.Orientation)
				
				local out_tp: Vector3 = Vector3.new(xz_check.Position.X, y_check.Position.Y, xz_check.Position.Z)
				local out_tn: Vector3 = Vector3.new(0, math.atan2(xz_check.Normal.X, xz_check.Normal.Z), 0)
				
				weld.Part0 = xz_check.Instance
				
				return __adjustForPlayerModel(out_tp, xz_check.Normal), out_tn
			end
			return nil, nil
		end
		return nil, nil
	end
	
	local checkInfoLookUp: {[string]: CheckStruct} = {
		
		["init"] = {
			y = 	{ first = Vector3.new(0,7,-0.9), 	second = -6 }, 
			xz = 	{ first = Vector3.zero, 			second = 1  },
			ortho = false
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
			
			Test.setWeldedPartCFrameAndPart1()
			weld2.C0 = handle.CFrame:ToObjectSpace(hrp.CFrame)
			
			print(weld2.C0)
			
			if extra_f then extra_f() end
			weld2.Enabled = true
			
			TweenCreation.createForHandle(tween_dur):Play()
			--TweenCreation.create(tween_dur):Play()
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
		
		weld2.Enabled = false
		
		hrp.Anchored = false
		hum.AutoRotate = true
		climbing = false
	end
	
	function ClimbingFunctions.moveAlongLedge()
		
		climbDir = _calc_climbXDir()
		
		for i=1, 3, 1 do
			if _updateClimbingStuff("sideways"..i, 0.2) then
				break
			end
		end
	end
	
	function ClimbingFunctions.moveVertically()
		
		--TODO: Implement vertical climbing (grabbing ledges that are above/below you)
		
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
		
		if not tweening then

			if uis:IsKeyDown(Enum.KeyCode.W) or
				uis:IsKeyDown(Enum.KeyCode.S) or
				uis:IsKeyDown(Enum.KeyCode.A) or
				uis:IsKeyDown(Enum.KeyCode.D)
			then
				ClimbingFunctions.moveAlongLedge()
			end
		end
		
		hrp.CFrame = player_pos.CFrame
	end
end)
