dofile("spacelib.lua")

--[[
API:
  AddSprite(string texturePath, Vec2 position, number rotation, Vec2 size) -> integer:
   - Create a new sprite using `texturePath` (if not empty) at `position` with an angle (in degrees) of `rotation` and a size of `size`
     Returns the sprite id which can be used to update any of the sprite properties at any time
	 If an empty texturePath is given, the sprite will be a white rectangle (which you can call UpdateSpriteColor upon)
   
  ClearSprites()
   - Clear/destroy every sprite, making every sprite id returned previously by AddSprite invalid
     This is automatically done when a script is reloaded

  DeleteSprite(integer id)
   - Destroy the sprite of id `id`
 
  GetScreenSize() -> table(width, height)
   - Return the application window size

  GetSpaceshipAngularVelocity() -> table(x, y, z)
   - Returns player controlled spaceship angular velocity

  GetSpaceshipLinearVelocity() -> table(x, y, z)
   - Returns player controlled spaceship linear velocity

  IsChatboxActive() -> boolean
   - Returns whether the chatbox is active (currently used for typing) or not

  PrintChatbox(string text)
   - Print something to the chat (which only the current player can see)

  Project(Vec3 worldPosition) -> table(x, y)
   - Returns the screen position corresponding to a world-space position (can be out of screenspace)
   
  RecenterMouse()
   - Center the mouse at the center of the window, whether it is visible or not

  ScanEntities() -> table(complex)
   - Scan the world and returns every entity in a table
      [unique_id] = {
        ["type"] = one of "spaceship", "projectile", "ball" and "earth"
        ["name"] = name of the entity, empty for projectiles
		["position"] = table(x, y, z)
		["rotation"] = table(x, y, z)
		["angularVelocity"] = table(x, y, z)
		["linearVelocity"] = table(x, y, z)
	  }
	This function is heavy, do not call it often

  Shoot()
   - Shoot a projectile (if possible) from the player spaceship
   
  ShowCursor(boolean show)
   - Show/hide the system mouse

  ShowHealthbar(boolean show)
   - Show/hide the application's default healthbar, allowing you to make your own (using event OnIntegrityUpdate)

  ShowSprite(integer id)
   - Show/hide a sprite by id, `id` must be valid

  UpdateCamera(Vec3 position, Quaternion rotation)
   - Sets the camera to a particular position and rotation, in worldspace.
     The camera is not attached to the spaceship, this function can be used to do it.
     Currently, the camera is not restricted and can move anywhere, this is intended but not a definitive behaviour

  UpdateSpriteColor(integer id, table color)
   - Changes the color (alpha included) of a sprite by id, `id` must be valid, `color` must contains at least fields "r", "g" and "b" (with a value between 0 and 255)
     You can also set a field "a" to set the new alpha value of the sprite.
	 You can use the utility Color function to easily create a color tabl.

  UpdateSpritePosition(integer id, Vec2 position, number rotation)
   - Changes the position and rotation of a sprite by id, `id` must be valid, `rotation` is in degrees.
  
  UpdateSpriteSize(integer id, Vec2 size)
   - Changes the size of a sprite by id, `id` must be valid.
   
Events:
  Events are Lua function called when something happens in the world, implementing them is not mandatory (with the exception of UpdateInput)
  Be warned that, due to technical reasons (and a bit of laziness), vectors and quaternions values parameters are NOT compatible with Vec2, Vec3 and Quaternion from spacelib.lua
  You have to recreate a valid Vec2/Vec3/Quaternion to use them correctly.

  Init()
   - Called just after the (re)loading of the Lua script.
     Be warned that everything is lost when a script is reloaded, as every variables from the previous script will be destroyed.
  
  OnKeyPressed(table event)
   - Called when a key is pressed/repeated
    Fields:
	 - string key: key name
	 - boolean alt: Was an Alt key pressed when the key was pressed
	 - boolean control: Was a Control key pressed when the key was pressed
	 - boolean repeated: Is this event generated by a repetition or not
	 - boolean shift: Was a Shift key pressed when the key was pressed 
	 - boolean system: Was a System key pressed when the key was pressed 

  OnKeyReleased(table event)
   - Called when a key is released
     Uses the same fields as the OnKeyPressed event
  
  OnLostFocus()
   - Called when the window loses focus, use this event to clear any key state to prevent troubles

  OnIntegrityUpdate(number integrity)
   - Called when your spaceship integrity values changes (currently only fired when you get hit or respawn)

  OnMouseButtonPressed(table event)
   - Called when a mouse button is pressed
    Fields:
	 - string button: button name
	 - integer x: X part of the mouse global position when the button was pressed
	 - integer y: Y part of the mouse global position when the button was pressed

  OnMouseButtonReleased(table event)
   - Called when a mouse button is pressed
     Uses the same fields as the OnMouseButtonPressed event

  OnMouseMoved(table event)
    - Called when the mouse moved (whether it is visible or not)
    Fields:
	 - integer x: X part of the mouse global position
	 - integer y: Y part of the mouse global position
	 - integer deltaX: X part of the mouse relative movement since the last event
	 - integer deltaY: Y part of the mouse relative movement since the last event

  OnUpdate(table(x, y, z) position, table(w, x, y, z) rotation)
   - Called every frame with the current position and rotation of the player's spaceship.
     Keep this function lightweight to preserve performances

  OnWindowSizeChanged(table size)
    - Called when the window gets resized
    Fields:
	 - integer width: Window new width
	 - integer height: Window new height

  UpdateInput(number elapsedTime) -> Vec3, Quaternion
    - Called every 60th of a second to gets the ship new inputs
	Must returns two variables:
	 - Vec3 acceleration: Ship new acceleration in local space
	 - Quaternion torque: Ship new torque in local space
]]

-- Constants
local Acceleration = 1.0  -- 100%
local AscensionSpeed = 0.66 -- 66%
local DistMax = 200
local RollSpeed = 0.66 -- 66%
local RotationSpeedPerPixel = 0.002  -- 0.2%
local StrafeSpeed = 0.66 -- 66%

-- Work vars
local CrosshairSprite
local KeyPressed = {}
local IsRotationEnabled = false
local MovementSprite
local MouseButtonPressed = {}
local RotationCursorPosition = Vec2.New(0, 0)
local ScreenSize


function Init()
	OnWindowSizeChanged(GetScreenSize())
	
	CrosshairSprite = AddSprite("Assets/weapons/crosshair.png", Vec2.New(0, 0), 0, Vec2.New(32, 32))
	MovementSprite = AddSprite("Assets/cursor/orientation.png", Vec2.New(0, 0), 0, Vec2.New(32, 32))
	ShowSprite(MovementSprite, false)
end

function OnKeyPressed(event)
	if (IsChatboxActive()) then
		return
	end

	if (event.key == "Space") then
		Shoot()
	else
		KeyPressed[event.key] = true
	end
end

function OnKeyReleased(event)
	KeyPressed[event.key] = false
end

function OnLostFocus()
	KeyPressed = {}
	MouseButtonPressed = {}
end

function OnMouseButtonPressed(event)
	MouseButtonPressed[event.button] = true
	if (event.button == "Right") then
		ShowCursor(false)
		IsRotationEnabled = true
		RotationCursorPosition = Vec2.New(0, 0)
		ShowSprite(MovementSprite, true)
		UpdateSpriteColor(MovementSprite, Color(255, 255, 255, 0))
	end
end

function OnMouseButtonReleased(event)
	MouseButtonPressed[event.button] = false
	if (event.button == "Right") then
		ShowCursor(true)
		IsRotationEnabled = false
		RotationCursorPosition = Vec2.New(0, 0)
		ShowSprite(MovementSprite, false)
	end
end

function OnMouseMoved(event)
	if (not IsRotationEnabled) then
		return
	end

	RotationCursorPosition.x = RotationCursorPosition.x + event.deltaX
	RotationCursorPosition.y = RotationCursorPosition.y + event.deltaY
	
	if (RotationCursorPosition:SquaredLength() > DistMax * DistMax) then
		RotationCursorPosition:Normalize()
		RotationCursorPosition = RotationCursorPosition * DistMax
	end

	local cursorAngle = math.deg(math.atan(RotationCursorPosition.y, RotationCursorPosition.x))
	local cursorAlpha = RotationCursorPosition:SquaredLength() / (DistMax * DistMax)
	UpdateSpritePosition(MovementSprite, ScreenSize * 0.5 + RotationCursorPosition, cursorAngle)
	UpdateSpriteColor(MovementSprite, Color(255, 255, 255, math.floor(cursorAlpha * 255)))

	RecenterMouse()
end

function OnUpdate(pos, rot)
	local position = Vec3.New(pos.x, pos.y, pos.z)
	local rotation = Quaternion.New(rot.w, rot.x, rot.y, rot.z)
		
	UpdateCamera(position + rotation * (Vec3.Backward * 12.0 + Vec3.Up * 5), rotation * Quaternion.FromEulerAngles(-10, 0.0, 0.0))
	
	local targetPos = position + rotation * (Vec3.Forward * 150)
	UpdateSpritePosition(CrosshairSprite, Project(targetPos), 0)
end

function OnWindowSizeChanged(size)
	ScreenSize = Vec2.New(size.width, size.height)
end

function UpdateInput(elapsedTime)
	if (KeyPressed["G"] or (MouseButtonPressed["Left"] and IsRotationEnabled)) then
		Shoot()
	end
	
	local SpaceshipMovement = Vec3.New()
	local SpaceshipRotation = Vec3.New()

	if (KeyPressed["Z"]) then
		SpaceshipMovement.x = SpaceshipMovement.x + Acceleration
	end

	if (KeyPressed["S"]) then
		SpaceshipMovement.x = SpaceshipMovement.x - Acceleration
	end

	local leftSpeedModifier = 0.0
	if (KeyPressed["Q"]) then
		SpaceshipMovement.y = SpaceshipMovement.y + StrafeSpeed
	end

	if (KeyPressed["D"]) then
		SpaceshipMovement.y = SpaceshipMovement.y - StrafeSpeed
	end

	local AscensionSpeedModifier = 0.0
	if (KeyPressed["LShift"]) then
		SpaceshipMovement.z = SpaceshipMovement.z + AscensionSpeed
	end

	if (KeyPressed["LControl"]) then
		SpaceshipMovement.z = SpaceshipMovement.z - AscensionSpeed
	end

	local rollSpeedModifier = 0.0
	if (KeyPressed["A"]) then
		SpaceshipRotation.z = SpaceshipRotation.z + RollSpeed
	end

	if (KeyPressed["E"]) then
		SpaceshipRotation.z = SpaceshipRotation.z - RollSpeed
	end

	local rotationDirection = RotationCursorPosition

	SpaceshipRotation.x = Clamp(-rotationDirection.y * RotationSpeedPerPixel, -1.0, 1.0)
	SpaceshipRotation.y = Clamp(-rotationDirection.x * RotationSpeedPerPixel, -1.0, 1.0)

	return SpaceshipMovement, SpaceshipRotation
end