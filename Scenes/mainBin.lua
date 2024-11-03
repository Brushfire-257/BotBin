-- The actual calculator for the program
mainBin = {}

local suit = require("Libraries/SUIT")

-- Colors
local minorGridColor = {1, 1, 1}       -- Grid lines
local mainAxisColor = {1, 1, 1}        -- Main axes

local boxFillColor = {0, 0, 1, 0.3}    -- Filled boxes
local boxBorderColor = {0, 0, 1}       -- Box borders
local newBoxFillColor = {0, 1, 0, 0.5} -- New box being created
local selectedBoxColor = {1, 1, 0}     -- Selected box border
local hoveredBoxColor = {1, 0.5, 0, 0.5} -- Hovered box fill color
local modeTextColor = {1, 1, 1}        -- Mode text at bottom
local locationTextColor = {1, 1, 1}    -- Location path text

-- Line Thicknesses
local baseGridLineWidth = 1            -- Base grid line width
local baseBoxBorderLineWidth = 2       -- Base box border line width
local baseMainAxisLineWidth = 2        -- Base main axis line width
local baseSelectedBoxLineWidth = 3     -- Base selected box line width

boxes = {}  -- Stores all boxes
currentBox = nil  -- The box we're currently inside (nil means we're at the root level)
boxStack = {}  -- Stack to keep track of nested boxes
local toolMode = "select"  -- Can be "select" or "create"
local newBox = nil  -- Temporary box being created
local startX, startY = nil, nil  -- Starting point of the new box

local hoveredBox = nil
local selectedBox = nil
local lastClickTime = 0
local doubleClickInterval = 0.4

-- Variables for smooth camera movement
local isMovingCamera = false
local movementStartX, movementStartY, movementStartZoom
local movementTargetX, movementTargetY, movementTargetZoom
local movementDuration = 0.5  -- Duration of camera movement in seconds
local movementElapsed = 0
local enteringBox = false

-- Variables for naming the box
local namingBox = nil  -- The box that needs to be named
local nameInput = { text = "" }  -- SUIT input field for the box name

local gridSpacing = 100  -- Distance between grid lines

local centerX = love.graphics.getWidth() / 2
local centerY = love.graphics.getHeight() / 2

local isDragging = false
local dragStartX, dragStartY = 0, 0

local currentLevel = 0  -- Level tracking

-- Variables for vector calculations
local textInput = { text = "" }
local vectorTable = {}
local requestedData = 0
local saveTable = {}
local prevVectorx, prevVectory = 0
local finalVectorx, finalVectory = 0, 0
local golfBallImage = love.graphics.newImage("Sprites/golfBall.png")
local golfBallRotationX = golfBallImage:getWidth() / 2
local golfBallRotationY = golfBallImage:getHeight() / 2
local golfBallAnimationTimer = 0

function mainBin.load()
    love.window.setTitle("BotBin")
    screenWidthA = love.graphics.getWidth()
    screenHeightA = love.graphics.getHeight()

    love.math.setRandomSeed(os.time())

    selectSound = love.audio.newSource("Sounds/select.wav", "stream")
    deselectSound = love.audio.newSource("Sounds/deselect.wav", "stream")

    -- Set SUIT colors
    suit.theme.color.normal.fg = {255,255,255}
    suit.theme.color.hovered = {bg = {200,230,255}, fg = {0,0,0}}
    suit.theme.color.active = {bg = {150,150,150}, fg = {0,0,0}}

    -- Load font
    font = love.graphics.newFont("Fonts/VCR_OSD_MONO.ttf", 100)
    font1 = love.graphics.newFont("Fonts/VCR_OSD_MONO.ttf", 75)
    font2 = love.graphics.newFont("Fonts/VCR_OSD_MONO.ttf", 50)
    font3 = love.graphics.newFont("Fonts/VCR_OSD_MONO.ttf", 25)
    love.graphics.setFont(font)
    love.keyboard.setKeyRepeat(true)
end

function mainBin.update(dt)

    if isMovingCamera then
        movementElapsed = movementElapsed + dt
        local t = math.min(movementElapsed / movementDuration, 1)

        -- Smooth interpolation (using smoothstep)
        local smoothT = t * t * (3 - 2 * t)

        centerX = movementStartX + (movementTargetX - movementStartX) * smoothT
        centerY = movementStartY + (movementTargetY - movementStartY) * smoothT
        gridSpacing = movementStartZoom + (movementTargetZoom - movementStartZoom) * smoothT

        if t >= 1 then
            isMovingCamera = false
        end
    else
        if namingBox then
            suit.layout:reset(love.graphics.getWidth() / 2 - 150, love.graphics.getHeight() / 2 - 25)
            suit.Label("Enter box name:", { align = "left" }, suit.layout:row(300, 60))
            suit.Input(nameInput, suit.layout:row())
            if suit.Button("OK", suit.layout:row()).hit or love.keyboard.isDown('return') then
                if nameInput.text ~= "" then
                    namingBox.name = nameInput.text
                    namingBox = nil
                    nameInput.text = ""
                end
            end
        else
            local locationTextHeight = font3:getHeight()
            local buttonY = 20 + locationTextHeight + 10

            -- if suit.Button("Select Tool", 20, buttonY, 100, 30).hit then
            --     toolMode = "select"
            -- end

            -- if suit.Button("Create Tool", 130, buttonY, 100, 30).hit then
            --     toolMode = "create"
            -- end

            if isDragging then
                local mouseX, mouseY = love.mouse.getPosition()
                local dx = mouseX - dragStartX
                local dy = mouseY - dragStartY

                centerX = centerX + dx
                centerY = centerY + dy

                dragStartX, dragStartY = mouseX, mouseY

                -- Cursor wrapping
                if mouseX <= 0 then
                    love.mouse.setPosition(screenWidthA - 1, mouseY)
                    dragStartX = screenWidthA - 1
                elseif mouseX >= screenWidthA - 1 then
                    love.mouse.setPosition(0, mouseY)
                    dragStartX = 0
                end

                if mouseY <= 0 then
                    love.mouse.setPosition(mouseX, screenHeightA - 1)
                    dragStartY = screenHeightA - 1
                elseif mouseY >= screenHeightA - 1 then
                    love.mouse.setPosition(mouseX, 0)
                    dragStartY = 0
                end
            end

            if newBox then
                local mouseX, mouseY = love.mouse.getPosition()
                local endX, endY = screenToGrid(mouseX, mouseY)
                newBox.width = math.abs(endX - startX)
                newBox.height = math.abs(endY - startY)
                newBox.x = math.min(startX, endX)
                newBox.y = math.min(startY, endY)
            end  

            if love.keyboard.isDown('[') then
                print("Returning to main menu")
                return "mainMenu"
            end

            -- Hover detection
            local mouseX, mouseY = love.mouse.getPosition()
            local gridX, gridY = screenToGrid(mouseX, mouseY, false)
            hoveredBox = findBoxAtPosition(gridX, gridY, getCurrentBoxChildren())


            -- suit.Input(textInput, screenWidthA - 350, 50, 300, 50)

            golfBallAnimationTimer = golfBallAnimationTimer + dt
        end
    end

    -- Handle vector input
    if requestedData == 0 then
        -- Waiting for magnitude
    elseif requestedData == 1 then
        -- Waiting for angle
    end
end

function love.mousepressed(x, y, button)
    if namingBox or isMovingCamera then
        return
    end

    if button == 1 then  -- Left Mouse Button for selection
        handleBoxSelection(x, y)
    elseif button == 3 then  -- Middle Mouse Button for dragging
        isDragging = true
        dragStartX, dragStartY = x, y
    elseif button == 2 or button == 3 then  -- Right Mouse Button for box creation
        startX, startY = screenToGrid(x, y)
        newBox = {x = startX, y = startY, width = 0, height = 0, children = {}}
    end
end

function love.mousereleased(x, y, button)
    if namingBox or isMovingCamera then
        return
    end

    if button == 3 then  -- Middle Mouse Button release stops dragging
        isDragging = false
    elseif (button == 2 or button == 3) and newBox then  -- Right Mouse Button release finalizes box creation
        local endX, endY = screenToGrid(x, y)
        newBox.width = math.abs(endX - startX)
        newBox.height = math.abs(endY - startY)
        newBox.x = math.min(startX, endX)
        newBox.y = math.min(startY, endY)

        if newBox.width == 0 or newBox.height == 0 then
            newBox = nil
        else
            table.insert(getCurrentBoxChildren(), newBox)
            namingBox = newBox
            newBox = nil
        end
    end
    if button == 3 then
        isDragging = false
    end
end

function handleBoxSelection(x, y)
    local gridX, gridY = screenToGrid(x, y, false)
    local box = findBoxAtPosition(gridX, gridY, getCurrentBoxChildren())
    local currentTime = love.timer.getTime()

    if box then
        if selectedBox == box and currentTime - lastClickTime < doubleClickInterval then
            table.insert(boxStack, currentBox)
            currentBox = box
            currentLevel = currentLevel + 1
            selectedBox = nil
            startCameraMovementToBox(box)
        else
            selectedBox = box
            lastClickTime = currentTime
        end
    else
        selectedBox = nil
    end
end

function startCameraMovementToBox(box)
    isMovingCamera = true
    movementElapsed = 0
    enteringBox = true

    movementStartX = centerX
    movementStartY = centerY
    movementStartZoom = gridSpacing

    local screenWidth, screenHeight = love.graphics.getDimensions()
    local marginFactor = 0.8

    local scaleX = (screenWidth * marginFactor) / box.width
    local scaleY = (screenHeight * marginFactor) / box.height
    movementTargetZoom = math.min(scaleX, scaleY)

    movementTargetX = screenWidth / 2 - (box.x + box.width / 2) * movementTargetZoom
    movementTargetY = screenHeight / 2 + (box.y + box.height / 2) * movementTargetZoom
end

function startCameraMovementToExitBox()
    isMovingCamera = true
    movementElapsed = 0
    enteringBox = false

    movementStartX = centerX
    movementStartY = centerY
    movementStartZoom = gridSpacing

    local screenWidth, screenHeight = love.graphics.getDimensions()
    local marginFactor = 0.8

    -- Get the box we're moving to (currentBox)
    local targetBox = currentBox or { x = 0, y = 0, width = 10, height = 10 }

    -- Calculate the target zoom level to fit the box on the screen
    local scaleX = (screenWidth * marginFactor) / targetBox.width
    local scaleY = (screenHeight * marginFactor) / targetBox.height
    movementTargetZoom = math.min(scaleX, scaleY)

    -- Calculate the target center position to center the box on the screen
    movementTargetX = screenWidth / 2 - (targetBox.x + targetBox.width / 2) * movementTargetZoom
    movementTargetY = screenHeight / 2 + (targetBox.y + targetBox.height / 2) * movementTargetZoom
end


function findBoxAtPosition(x, y, boxList)
    for _, box in ipairs(boxList) do
        if x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height then
            return box
        end
    end
    return nil
end

function mainBin.draw()
    love.graphics.clear(2 / 255, 10 / 255, 14 / 255)
    love.graphics.setFont(font3)

    local screenWidth, screenHeight = love.graphics.getDimensions()

    -- Calculate line widths based on current level
    gridLineWidth = baseGridLineWidth / (currentLevel + 1)
    boxBorderLineWidth = baseBoxBorderLineWidth / (currentLevel + 1)
    mainAxisLineWidth = baseMainAxisLineWidth / (currentLevel + 1)
    selectedBoxLineWidth = baseSelectedBoxLineWidth / (currentLevel + 1)

    -- Draw grid lines
    love.graphics.setColor(minorGridColor)
    love.graphics.setLineWidth(gridLineWidth)
    drawGridLines(centerX, centerY, gridSpacing, screenWidth, screenHeight)

    -- Draw main axes
    love.graphics.setColor(mainAxisColor)
    love.graphics.setLineWidth(mainAxisLineWidth)
    love.graphics.line(0, centerY, screenWidth, centerY)  -- x-axis
    love.graphics.line(centerX, 0, centerX, screenHeight)  -- y-axis

    drawBoxes(getCurrentBoxChildren())

    if newBox then
        love.graphics.setColor(newBoxFillColor)
        local x1, y1 = gridToScreen(newBox.x, newBox.y)
        local x2, y2 = gridToScreen(newBox.x + newBox.width, newBox.y + newBox.height)
        local x = math.min(x1, x2)
        local y = math.min(y1, y2)
        local width = math.abs(x2 - x1)
        local height = math.abs(y2 - y1)
        love.graphics.rectangle("fill", x, y, width, height)
    end

    if selectedBox then
        love.graphics.setColor(selectedBoxColor)
        love.graphics.setLineWidth(selectedBoxLineWidth)
        local x1, y1 = gridToScreen(selectedBox.x, selectedBox.y)
        local x2, y2 = gridToScreen(selectedBox.x + selectedBox.width, selectedBox.y + selectedBox.height)
        local x = math.min(x1, x2)
        local y = math.min(y1, y2)
        local width = math.abs(x2 - x1)
        local height = math.abs(y2 - y1)
        love.graphics.rectangle("line", x, y, width, height)
    end

    -- GUI
    love.graphics.setColor(0, 0, 0.1)
    print(screenWidthA .. ", " .. screenHeightA)
    love.graphics.rectangle("fill", 0, 0, screenWidthA, 100)

    love.graphics.setFont(font3)
    -- love.graphics.setColor(modeTextColor)
    -- love.graphics.print("Mode: " .. (toolMode == "select" and "Select" or "Create"), 20, 50)

    love.graphics.setColor(locationTextColor)
    love.graphics.print("Location: " .. getLocationPath(), 20, 20)

    if currentBox then
        love.graphics.setColor(selectedBoxColor)
        love.graphics.setLineWidth(selectedBoxLineWidth)
        local x1, y1 = gridToScreen(currentBox.x, currentBox.y)
        local x2, y2 = gridToScreen(currentBox.x + currentBox.width, currentBox.y + currentBox.height)
        local x = math.min(x1, x2)
        local y = math.min(y1, y2)
        local width = math.abs(x2 - x1)
        local height = math.abs(y2 - y1)
        love.graphics.rectangle("line", x, y, width, height)
    end

    if currentBox and #boxStack > 0 then
        local parentBox = boxStack[#boxStack]
        love.graphics.setColor(0, 0, .5, 0.1)
        local x1, y1 = gridToScreen(parentBox.x, parentBox.y)
        local x2, y2 = gridToScreen(parentBox.x + parentBox.width, parentBox.y + parentBox.height)
        local x = math.min(x1, x2)
        local y = math.min(y1, y2)
        local width = math.abs(x2 - x1)
        local height = math.abs(y2 - y1)
        love.graphics.rectangle("fill", x, y, width, height)
    elseif currentBox then
        love.graphics.setColor(0, 0, 0.5, 0.1)
        love.graphics.setLineWidth(selectedBoxLineWidth)
        local x1, y1 = gridToScreen(currentBox.x, currentBox.y)
        local x2, y2 = gridToScreen(currentBox.x + currentBox.width, currentBox.y + currentBox.height)
        local x = math.min(x1, x2)
        local y = math.min(y1, y2)
        local width = math.abs(x2 - x1)
        local height = math.abs(y2 - y1)
        love.graphics.rectangle("fill", x, y, width, height)
    end
end

function drawGridLines(centerX, centerY, spacing, screenWidth, screenHeight)
    for x = centerX % spacing, screenWidth, spacing do
        love.graphics.line(x, 0, x, screenHeight)
    end
    for y = centerY % spacing, screenHeight, spacing do
        love.graphics.line(0, y, screenWidth, y)
    end
end

function drawBoxes(boxList)
    for _, box in ipairs(boxList) do
        local x1, y1 = gridToScreen(box.x, box.y)
        local x2, y2 = gridToScreen(box.x + box.width, box.y + box.height)
        local x = math.min(x1, x2)
        local y = math.min(y1, y2)
        local width = math.abs(x2 - x1)
        local height = math.abs(y2 - y1)
        
        if box == hoveredBox then
            love.graphics.setColor(hoveredBoxColor)
        else
            love.graphics.setColor(boxFillColor)
        end
        love.graphics.rectangle("fill", x, y, width, height)

        love.graphics.setColor(boxBorderColor)
        love.graphics.setLineWidth(boxBorderLineWidth)
        love.graphics.rectangle("line", x, y, width, height)

        if box.name then
            love.graphics.setColor(1, 1, 1)
            love.graphics.setFont(font3)
            local textWidth = font3:getWidth(box.name)
            local textHeight = font3:getHeight()
            love.graphics.print(box.name, x + width / 2 - textWidth / 2, y + height / 2 - textHeight / 2)
        end
    end
end

function getLocationPath()
    local path = "Root"
    for _, box in ipairs(boxStack) do
        path = path .. "/" .. (box.name or "Box")
    end
    if currentBox then
        path = path .. "/" .. (currentBox.name or "Box")
    end
    return path
end

function screenToGrid(x, y, doRound)
    local gridX = (x - centerX) / gridSpacing
    local gridY = (centerY - y) / gridSpacing
    if doRound == nil then
        doRound = true
    end
    if doRound then
        gridX = roundToGrid(gridX)
        gridY = roundToGrid(gridY)
    end
    return gridX, gridY
end

function gridToScreen(x, y)
    local screenX = centerX + x * gridSpacing
    local screenY = centerY - y * gridSpacing
    return screenX, screenY
end

function roundToGrid(num)
    local baseIncrement = 0.5
    local gridIncrement = baseIncrement / (2 ^ currentLevel)
    return math.floor(num / gridIncrement + 0.5) * gridIncrement
end

function getCurrentBoxChildren()
    if currentBox then
        return currentBox.children
    else
        return boxes
    end
end

function addVectors(vectorTable)
    local vectorx, vectory = 0, 0
    for i, vector in ipairs(vectorTable) do
        if i == 1 then
            vectorx, vectory = deconstructVector(vector[1], vector[2])
        else
            local vx, vy = deconstructVector(vector[1], vector[2])
            vectorx = vectorx + vx
            vectory = vectory + vy
        end

        local color1 = {50 / 255, 150 / 255, 200 / 255}
        local color2 = {200 / 255, 200 / 255, 255 / 255}
        local normalized = (i - 1) / (#vectorTable - 1)
        local r = (1 - normalized) * color1[1] + normalized * color2[1]
        local g = (1 - normalized) * color1[2] + normalized * color2[2]
        local b = (1 - normalized) * color1[3] + normalized * color2[3]

        if i == 1 then
            drawLine(0, 0, vectorx, vectory, 5, {r, g, b})
        else
            drawLine(0, 0, vectorx, vectory, 5, {r, g, b})
        end
    end

    finalVectorx = vectorx
    finalVectory = vectory
end

function deconstructVector(magnitude, direction)
    local vectorx = magnitude * math.cos(math.rad(direction))
    local vectory = magnitude * math.sin(math.rad(direction))
    return vectorx, vectory
end

function drawLine(startX, startY, endX, endY, thickness, color)
    local screenStartX = centerX + startX * gridSpacing
    local screenStartY = centerY - startY * gridSpacing
    local screenEndX = centerX + endX * gridSpacing
    local screenEndY = centerY - endY * gridSpacing

    love.graphics.setLineWidth(thickness)
    love.graphics.setColor(color[1], color[2], color[3])
    love.graphics.line(screenStartX, screenStartY, screenEndX, screenEndY)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

function printFinal()
    local finalVectorMagnitude = math.sqrt((finalVectorx^2) + (finalVectory^2))
    local finalVectorAngle = math.deg(math.atan2(finalVectory, finalVectorx))
    love.graphics.print("Ans: <" .. roundNumber(finalVectorMagnitude, 3) .. "," .. roundNumber(finalVectorAngle, 3) .. ">", 0, screenHeightA - 50)
end

function roundNumber(number, decimalPlaces)
    return math.floor(number * (10 ^ decimalPlaces) + 0.5) / (10 ^ decimalPlaces)
end

function love.wheelmoved(x, y)
    if y == 0 then return end

    local oldGridSpacing = gridSpacing
    local zoomFactor = 1.1
    if y > 0 then
        -- Zoom in
        gridSpacing = gridSpacing * zoomFactor
    elseif y < 0 then
        -- Zoom out
        gridSpacing = gridSpacing / zoomFactor
    end

    -- Clamp gridSpacing to a reasonable range
    if gridSpacing < 20 then
        gridSpacing = 20
    elseif gridSpacing > 1200 then
        gridSpacing = 1200
    end

    -- Adjust centerX and centerY to zoom towards the mouse position
    local mouseX, mouseY = love.mouse.getPosition()
    local worldX_beforeZoom = (mouseX - centerX) / oldGridSpacing
    local worldY_beforeZoom = (mouseY - centerY) / oldGridSpacing

    local worldX_afterZoom = (mouseX - centerX) / gridSpacing
    local worldY_afterZoom = (mouseY - centerY) / gridSpacing

    centerX = centerX + (worldX_afterZoom - worldX_beforeZoom) * gridSpacing
    centerY = centerY + (worldY_afterZoom - worldY_beforeZoom) * gridSpacing
end


function mainBin.drawSUIT()
    suit.draw()
end

function love.textinput(t)
    suit.textinput(t)
end

function love.keypressed(key)
    suit.keypressed(key)
    if namingBox or isMovingCamera then
        return
    end

    if key == "escape" and currentBox then
        -- Store the box we are exiting from
        currentBox = table.remove(boxStack)
        currentLevel = currentLevel - 1

        -- Start camera movement to center on the current box (parent box)
        startCameraMovementToExitBox()
    elseif key == "]" then
        love.event.quit()
    elseif key == "c" then
        centerX = love.graphics.getWidth() / 2
        centerY = love.graphics.getHeight() / 2
    elseif key == "r" then
        vectorTable = {}
        prevVectorx, prevVectory = 0, 0
    elseif key == "return" then
        local savedValue = tonumber(textInput.text)

        if requestedData == 0 then
            if savedValue ~= nil then
                saveTable[1] = savedValue
                textInput.text = ""
                requestedData = 1
            end
        elseif requestedData == 1 then
            if savedValue ~= nil then
                saveTable[2] = savedValue
                textInput.text = ""
                table.insert(vectorTable, {saveTable[1], saveTable[2]})
                saveTable = {}
                requestedData = 0
            end
        end 
    end
end

return mainBin
