--!strict

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 1 - START")

------------------------------------------------------------
-- DEBUG PRINT MANAGER
--
-- Main features:
--
--   DISABLE ALL
--       Disable standalone print(...) statements across
--       the entire place.
--
--   RESTORE ALL
--       Restore only print statements disabled by this
--       plugin across the entire place.
--
--   DISABLE SELECTED
--       Disable prints only inside the current Studio
--       selection.
--
--   RESTORE SELECTED
--       Restore plugin-disabled prints only inside the
--       current Studio selection.
--
--   ENABLE ONLY SELECTED
--       Restore plugin-disabled prints in the selection
--       and disable prints everywhere else.
--
--   IGNORE PACKAGES
--       Package scripts are skipped entirely when enabled.
--       The setting persists between Studio sessions.
--
--   STATISTICS
--       Shows place-wide and selection statistics.
--
--   DOCKABLE UI
--       Main controls are contained inside a Studio
--       DockWidgetPluginGui.
--
-- Selection supports:
--
--   Script
--   LocalScript
--   ModuleScript
--   Folder
--   Model
--   Multiple selected objects
--
-- Disabled lines are preserved using:
--
--   -- [DEBUG_PRINT_MANAGER_DISABLED]
--
-- Restore ONLY removes that exact marker.
--
-- IMPORTANT:
-- Use the plugin in Studio EDIT MODE.
------------------------------------------------------------

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------

local ScriptEditorService =
	game:GetService("ScriptEditorService")

local ChangeHistoryService =
	game:GetService("ChangeHistoryService")

local Selection =
	game:GetService("Selection")

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------

local DISABLED_MARKER =
	"-- [DEBUG_PRINT_MANAGER_DISABLED] "

local IGNORE_PACKAGES_SETTING =
	"IgnorePackages"

------------------------------------------------------------
-- PLUGIN SETTINGS
------------------------------------------------------------

local ignorePackages =
	true

------------------------------------------------------------
-- TOOLBAR
------------------------------------------------------------

local toolbar =
	plugin:CreateToolbar(
		"Debug Print Manager"
	)

local toolbarButton =
	toolbar:CreateButton(
		"DebugPrintManager",
		"Open Debug Print Manager",
		"rbxassetid://14978048121",
		"Debug Prints"
	)

toolbarButton.ClickableWhenViewportHidden =
	true

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 2 - TOOLBAR CREATED")

------------------------------------------------------------
-- LOAD PLUGIN SETTINGS
------------------------------------------------------------

do
	local ok, storedValue =
		pcall(
			function()
				return plugin:GetSetting(
					IGNORE_PACKAGES_SETTING
				)
			end
		)

	if ok
		and type(storedValue) == "boolean"
	then

		ignorePackages =
			storedValue
	end
end

------------------------------------------------------------
-- TYPES
------------------------------------------------------------

type PrintRange = {
	startLine: number,
	endLine: number,
}

type OperationStats = {
	scriptsScanned: number,
	scriptsChanged: number,
	printsAffected: number,
	failedScripts: number,
	ignoredPackageScripts: number,
}

------------------------------------------------------------
-- LONG BRACKET DETECTION
--
-- Supports:
--
--   [[ ... ]]
--   [=[ ... ]=]
--   [==[ ... ]==]
------------------------------------------------------------

local function getLongBracketLevel(
	source: string,
	position: number
): number?

	if source:sub(
		position,
		position
		) ~= "[" then

		return nil
	end

	local cursor =
		position + 1

	local equalsCount =
		0

	while source:sub(
		cursor,
		cursor
		) == "=" do

		equalsCount += 1
		cursor += 1
	end

	if source:sub(
		cursor,
		cursor
		) == "[" then

		return equalsCount
	end

	return nil
end

local function findLongBracketClose(
	source: string,
	startPosition: number,
	level: number
): number?

	local closeToken =
		"]"
		.. string.rep(
			"=",
			level
		)
		.. "]"

	return source:find(
		closeToken,
		startPosition,
		true
	)
end

------------------------------------------------------------
-- QUOTED STRING SKIP
------------------------------------------------------------

local function skipQuotedString(
	source: string,
	startPosition: number,
	quote: string
): number

	local length =
		#source

	local position =
		startPosition + 1

	while position <= length do

		local character =
			source:sub(
				position,
				position
			)

		if character == "\\" then

			position += 2

		elseif character == quote then

			return position + 1

		else

			position += 1
		end
	end

	return length + 1
end

------------------------------------------------------------
-- BACKTICK STRING SKIP
------------------------------------------------------------

local function skipBacktickString(
	source: string,
	startPosition: number
): number

	local length =
		#source

	local position =
		startPosition + 1

	while position <= length do

		local character =
			source:sub(
				position,
				position
			)

		if character == "\\" then

			position += 2

		elseif character == "`" then

			return position + 1

		else

			position += 1
		end
	end

	return length + 1
end

------------------------------------------------------------
-- FIND MATCHING PARENTHESIS
------------------------------------------------------------

local function findMatchingParenthesis(
	source: string,
	openPosition: number
): number?

	local length =
		#source

	local position =
		openPosition

	local depth =
		0

	while position <= length do

		local character =
			source:sub(
				position,
				position
			)

		----------------------------------------------------
		-- PARENTHESIS
		----------------------------------------------------

		if character == "(" then

			depth += 1
			position += 1

			continue
		end

		if character == ")" then

			depth -= 1

			if depth == 0 then

				return position
			end

			position += 1

			continue
		end

		----------------------------------------------------
		-- QUOTED STRING
		----------------------------------------------------

		if character == "'"
			or character == '"' then

			position =
				skipQuotedString(
					source,
					position,
					character
				)

			continue
		end

		----------------------------------------------------
		-- BACKTICK STRING
		----------------------------------------------------

		if character == "`" then

			position =
				skipBacktickString(
					source,
					position
				)

			continue
		end

		----------------------------------------------------
		-- COMMENT
		----------------------------------------------------

		if character == "-"
			and source:sub(
				position + 1,
				position + 1
			) == "-" then

			local longLevel =
				getLongBracketLevel(
					source,
					position + 2
				)

			if longLevel ~= nil then

				local closePosition =
					findLongBracketClose(
						source,
						position + 2,
						longLevel
					)

				if closePosition then

					position =
						closePosition
						+ 2
						+ longLevel

					continue
				end

				return nil
			end

			local newlinePosition =
				source:find(
					"\n",
					position + 2,
					true
				)

			if newlinePosition then

				position =
					newlinePosition

			else

				position =
					length + 1
			end

			continue
		end

		----------------------------------------------------
		-- LONG STRING
		----------------------------------------------------

		if character == "[" then

			local longLevel =
				getLongBracketLevel(
					source,
					position
				)

			if longLevel ~= nil then

				local closePosition =
					findLongBracketClose(
						source,
						position + 1,
						longLevel
					)

				if closePosition then

					position =
						closePosition
						+ 2
						+ longLevel

					continue
				end

				return nil
			end
		end

		position += 1
	end

	return nil
end

------------------------------------------------------------
-- FIND IDENTIFIER CHARACTER
------------------------------------------------------------

local function isIdentifierCharacter(
	character: string?
): boolean

	if character == nil
		or character == "" then

		return false
	end

	return string.match(
		character,
		"[%w_]"
	) ~= nil
end

------------------------------------------------------------
-- HORIZONTAL WHITESPACE
------------------------------------------------------------

local function isHorizontalWhitespace(
	character: string?
): boolean

	return character == " "
		or character == "\t"
		or character == "\r"
end

------------------------------------------------------------
-- COUNT NEWLINES
------------------------------------------------------------

local function countNewlines(
	source: string,
	startPosition: number,
	endPosition: number
): number

	local substring =
		source:sub(
			startPosition,
			endPosition
		)

	local _, count =
		substring:gsub(
			"\n",
			""
		)

	return count
end

------------------------------------------------------------
-- FIND STANDALONE PRINT CALLS
------------------------------------------------------------
--
-- Safe/conservative detector.
--
-- Detects:
--
--     print("hello")
--
--     print(
--         "hello",
--         value
--     )
--
-- Does not touch:
--
--     local x = print("hello")
--     foo(print("hello"))
--     if x then print("hello") end
--
------------------------------------------------------------

------------------------------------------------------------
-- FIND STANDALONE PRINT CALLS
--
-- Supports standalone prints:
--
--     print("hello")
--
--     print(
--         "hello",
--         value
--     )
--
-- Also correctly detects prints inside callbacks such as:
--
--     SomeEvent:Connect(
--         function()
--             print("hello")
--         end
--     )
--
-- Does NOT detect a print that is simply an expression
-- argument:
--
--     SomeFunction(
--         print("hello")
--     )
--
-- because that would be part of the surrounding expression.
------------------------------------------------------------

local function findStandalonePrintCalls(
	source: string
): {PrintRange}

	local ranges: {
		PrintRange
	} = {}

	local length =
		#source

	local position =
		1

	local lineNumber =
		1

	local parenthesisDepth =
		0

	local braceDepth =
		0

	local squareBracketDepth =
		0

	--------------------------------------------------------
	-- FUNCTION BODY TRACKING
	--
	-- We need this because:
	--
	-- Connect(
	--     function()
	--         print(...)
	--     end
	-- )
	--
	-- still has parenthesisDepth > 0 while the print is
	-- executing inside the callback body.
	--------------------------------------------------------

	local blockStack: {
		string
	} = {}

	local function getFunctionDepth(): number

		local count =
			0

		for _, blockType in ipairs(
			blockStack
			) do

			if blockType == "function" then
				count += 1
			end
		end

		return count
	end

	local function pushBlock(
		blockType: string
	)

		table.insert(
			blockStack,
			blockType
		)
	end

	local function popEndBlock()

		if #blockStack > 0 then

			table.remove(
				blockStack
			)
		end
	end

	local function popRepeatBlock()

		for index =
			#blockStack,
			1,
			-1
		do

			if blockStack[index] == "repeat" then

				table.remove(
					blockStack,
					index
				)

				return
			end
		end
	end

	--------------------------------------------------------
	-- IDENTIFIER SCAN
	--------------------------------------------------------

	local function readIdentifier(
		startPosition: number
	)

		local firstCharacter =
			source:sub(
				startPosition,
				startPosition
			)

		if not (
			firstCharacter:match(
				"[%a_]"
			)
			) then

			return nil
		end

		local cursor =
			startPosition + 1

		while cursor <= length do

			local character =
				source:sub(
					cursor,
					cursor
				)

			if not character:match(
				"[%w_]"
				) then

				break
			end

			cursor += 1
		end

		return
			source:sub(
				startPosition,
				cursor - 1
			),
			cursor
	end

	--------------------------------------------------------
	-- MAIN SCANNER
	--------------------------------------------------------

	while position <= length do

		local character =
			source:sub(
				position,
				position
			)

		----------------------------------------------------
		-- NEWLINE
		----------------------------------------------------

		if character == "\n" then

			lineNumber += 1
			position += 1

			continue
		end

		----------------------------------------------------
		-- QUOTED STRING
		----------------------------------------------------

		if character == "'"
			or character == '"' then

			position =
				skipQuotedString(
					source,
					position,
					character
				)

			continue
		end

		----------------------------------------------------
		-- BACKTICK STRING
		----------------------------------------------------

		if character == "`" then

			position =
				skipBacktickString(
					source,
					position
				)

			continue
		end

		----------------------------------------------------
		-- COMMENTS
		--
		-- IMPORTANT:
		-- The second character must be "-"
		----------------------------------------------------

		if character == "-"
			and source:sub(
				position + 1,
				position + 1
			) == "-" then

			local longLevel =
				getLongBracketLevel(
					source,
					position + 2
				)

			if longLevel ~= nil then

				local closePosition =
					findLongBracketClose(
						source,
						position + 2,
						longLevel
					)

				if closePosition then

					local skippedText =
						source:sub(
							position,
							closePosition
							+ 1
							+ longLevel
						)

					local _, newlineCount =
						skippedText:gsub(
							"\n",
							""
						)

					lineNumber +=
						newlineCount

					position =
						closePosition
						+ 2
						+ longLevel

					continue
				end

				break
			end

			local newlinePosition =
				source:find(
					"\n",
					position + 2,
					true
				)

			if newlinePosition then

				position =
					newlinePosition

			else

				position =
					length + 1
			end

			continue
		end

		----------------------------------------------------
		-- LONG STRING
		----------------------------------------------------

		if character == "[" then

			local longLevel =
				getLongBracketLevel(
					source,
					position
				)

			if longLevel ~= nil then

				local closePosition =
					findLongBracketClose(
						source,
						position + 1,
						longLevel
					)

				if closePosition then

					local skippedText =
						source:sub(
							position,
							closePosition
							+ 1
							+ longLevel
						)

					local _, newlineCount =
						skippedText:gsub(
							"\n",
							""
						)

					lineNumber +=
						newlineCount

					position =
						closePosition
						+ 2
						+ longLevel

					continue
				end

				break
			end
		end

		----------------------------------------------------
		-- CHECK FOR print() AT PHYSICAL LINE START
		----------------------------------------------------

		local atLineStart =
			position == 1
			or source:sub(
				position - 1,
				position - 1
			) == "\n"

		if atLineStart then

			local candidate =
				position

			------------------------------------------------
			-- Skip indentation.
			------------------------------------------------

			while candidate <= length
				and isHorizontalWhitespace(
					source:sub(
						candidate,
						candidate
					)
				) do

				candidate += 1
			end

			local functionDepth =
				getFunctionDepth()

			------------------------------------------------
			-- Safe contexts:
			--
			-- 1. Completely top-level expression state.
			--
			-- 2. Inside a function body.
			--
			-- This is what allows:
			--
			-- Connect(function()
			--     print(...)
			-- end)
			------------------------------------------------

			local safeContext =
				(
					parenthesisDepth == 0
					and braceDepth == 0
					and squareBracketDepth == 0
				)
				or (
					functionDepth > 0
					and braceDepth == 0
					and squareBracketDepth == 0
				)

			if safeContext then

				local printEnd =
					candidate + 4

				if source:sub(
					candidate,
					printEnd
					) == "print" then

					local previousCharacter =
						source:sub(
							candidate - 1,
							candidate - 1
						)

					local nextCharacter =
						source:sub(
							printEnd + 1,
							printEnd + 1
						)

					local validPrevious =
						candidate == 1
						or not isIdentifierCharacter(
							previousCharacter
						)

					local validNext =
						nextCharacter == ""
						or not isIdentifierCharacter(
							nextCharacter
						)

					if validPrevious
						and validNext then

						local openPosition =
							printEnd + 1

						while openPosition <= length
							and isHorizontalWhitespace(
								source:sub(
									openPosition,
									openPosition
								)
							) do

							openPosition += 1
						end

						if source:sub(
							openPosition,
							openPosition
							) == "(" then

							local closePosition =
								findMatchingParenthesis(
									source,
									openPosition
								)

							if closePosition ~= nil then

								local after =
									closePosition + 1

								while after <= length
									and isHorizontalWhitespace(
										source:sub(
											after,
											after
										)
									) do

									after += 1
								end

								------------------------------------------------
								-- Optional semicolon.
								------------------------------------------------

								if source:sub(
									after,
									after
									) == ";" then

									after += 1

									while after <= length
										and isHorizontalWhitespace(
											source:sub(
												after,
												after
											)
										) do

										after += 1
									end
								end

								local validTerminator =
									after > length
									or source:sub(
										after,
										after
									) == "\n"
									or source:sub(
										after,
										after + 1
									) == "--"

								if validTerminator then

									local endLine =
										lineNumber
										+ countNewlines(
											source,
											position,
											closePosition
										)

									table.insert(
										ranges,
										{
											startLine =
												lineNumber,

											endLine =
												endLine,
										}
									)
								end
							end
						end
					end
				end
			end
		end

		----------------------------------------------------
		-- IDENTIFIERS / BLOCK TRACKING
		----------------------------------------------------


		local identifier,
			nextIdentifierPosition =
			readIdentifier(
				position
			)

		if identifier ~= nil then

			------------------------------------------------
			-- FUNCTION
			------------------------------------------------

			if identifier == "function" then

				pushBlock(
					"function"
				)

				------------------------------------------------
				-- IF
				------------------------------------------------

			elseif identifier == "if" then

				pushBlock(
					"if"
				)

				------------------------------------------------
				-- FOR
				------------------------------------------------

			elseif identifier == "for" then

				pushBlock(
					"for"
				)

				------------------------------------------------
				-- WHILE
				------------------------------------------------

			elseif identifier == "while" then

				pushBlock(
					"while"
				)

				------------------------------------------------
				-- DO
				------------------------------------------------
				-- A "for" or "while" already represents the
				-- block that will be closed by its "end".
				-- Therefore its "do" does not get another
				-- stack entry.
				------------------------------------------------

			elseif identifier == "do" then

				local lastBlock =
					blockStack[#blockStack]

				if lastBlock ~= "for"
					and lastBlock ~= "while"
				then

					pushBlock(
						"do"
					)
				end

				------------------------------------------------
				-- REPEAT
				------------------------------------------------

			elseif identifier == "repeat" then

				pushBlock(
					"repeat"
				)

				------------------------------------------------
				-- END
				------------------------------------------------

			elseif identifier == "end" then

				popEndBlock()

				------------------------------------------------
				-- UNTIL
				------------------------------------------------

			elseif identifier == "until" then

				popRepeatBlock()
			end

			position =
				nextIdentifierPosition

			continue
		end
		----------------------------------------------------
		-- DEPTH TRACKING
		----------------------------------------------------



		if character == "(" then

			parenthesisDepth += 1

		elseif character == ")" then

			parenthesisDepth =
				math.max(
					0,
					parenthesisDepth - 1
				)

		elseif character == "{" then

			braceDepth += 1

		elseif character == "}" then

			braceDepth =
				math.max(
					0,
					braceDepth - 1
				)

		elseif character == "[" then

			squareBracketDepth += 1

		elseif character == "]" then

			squareBracketDepth =
				math.max(
					0,
					squareBracketDepth - 1
				)
		end


		position += 1
	end

	return ranges
end

------------------------------------------------------------
-- SPLIT SOURCE INTO LINES
------------------------------------------------------------

local function splitLines(
	source: string
): {string}

	local lines: {
		string
	} = {}

	local position =
		1

	local length =
		#source

	while position <= length do

		local newlineStart =
			source:find(
				"\n",
				position,
				true
			)

		if newlineStart == nil then

			table.insert(
				lines,
				source:sub(
					position
				)
			)

			break
		end

		local lineEnd =
			newlineStart

		if lineEnd > position
			and source:sub(
				lineEnd - 1,
				lineEnd - 1
			) == "\r" then

			lineEnd -= 1
		end

		local newlineText =
			source:sub(
				lineEnd + 1,
				newlineStart
			)

		table.insert(
			lines,
			source:sub(
				position,
				lineEnd
			)
				.. newlineText
		)

		position =
			newlineStart + 1
	end

	if #lines == 0 then

		lines[1] =
			""
	end

	return lines
end

------------------------------------------------------------
-- CHECK WHETHER A SCRIPT IS INSIDE A PACKAGE
--
-- Roblox package copies contain a PackageLink object at
-- the package root. Walking ancestors allows this to work
-- for scripts nested at any depth and nested packages.
------------------------------------------------------------

local function isInsidePackage(
	instance: Instance
): boolean

	local current:
		Instance? =
		instance

	while current
		and current ~= game
	do

		if current:FindFirstChildOfClass(
			"PackageLink"
			) then

			return true
		end

		current =
			current.Parent
	end

	return false
end

------------------------------------------------------------
-- DISABLE PRINTS IN ONE SOURCE
------------------------------------------------------------

local function disablePrintsInSource(
	source: string
): (string, number)

	local ranges =
		findStandalonePrintCalls(
			source
		)

	if #ranges == 0 then

		return source, 0
	end

	local disabledLines:
		{[number]: boolean} =
		{}

	for _, range in ipairs(
		ranges
		) do

		for lineIndex =
			range.startLine,
			range.endLine
		do

			disabledLines[lineIndex] =
				true
		end
	end

	local lines =
		splitLines(
			source
		)

	for lineIndex, line in ipairs(
		lines
		) do

		local alreadyDisabled =
			line:sub(
				1,
				#DISABLED_MARKER
			) == DISABLED_MARKER

		if disabledLines[lineIndex]
			and not alreadyDisabled then

			lines[lineIndex] =
				DISABLED_MARKER
				.. line
		end
	end

	return table.concat(
		lines
	), #ranges
end

------------------------------------------------------------
-- RESTORE PRINTS IN ONE SOURCE
--
-- ONLY removes the exact plugin marker.
------------------------------------------------------------

local function restorePrintsInSource(
	source: string
): (string, number)

	local lines =
		splitLines(
			source
		)

	local restoredLineCount =
		0

	for lineIndex, line in ipairs(
		lines
		) do

		if line:sub(
			1,
			#DISABLED_MARKER
			) == DISABLED_MARKER then

			lines[lineIndex] =
				line:sub(
					#DISABLED_MARKER + 1
				)

			restoredLineCount += 1
		end
	end

	if restoredLineCount == 0 then

		return source, 0
	end

	return table.concat(
		lines
	), restoredLineCount
end

------------------------------------------------------------
-- COUNT DISABLED PRINT STATEMENTS
--
-- A multiline disabled print has multiple marked lines,
-- so we count only the marker line whose original content
-- begins with print(...).
------------------------------------------------------------

local function countDisabledPrintStatements(
	source: string
): number

	local count =
		0

	for line in source:gmatch(
		"[^\n]*"
		) do

		if line:sub(
			1,
			#DISABLED_MARKER
			) == DISABLED_MARKER then

			local originalLine =
				line:sub(
					#DISABLED_MARKER + 1
				)

			local content =
				originalLine:match(
					"^%s*(.-)%s*$"
				)
				or ""

			if content:sub(
				1,
				5
				) == "print" then

				local characterAfterPrint =
					content:sub(
						6,
						6
					)

				if characterAfterPrint == "("
					or characterAfterPrint == " "
					or characterAfterPrint == "\t"
				then

					local afterPrint =
						content:sub(
							6
						):match(
						"^%s*%("
					)

					if afterPrint then
						count += 1
					end
				end
			end
		end
	end

	return count
end

------------------------------------------------------------
-- GET EVERY SCRIPT IN THE PLACE
------------------------------------------------------------

local function getScriptsInPlace(): {
	LuaSourceContainer
	}

	local scripts: {
		LuaSourceContainer
	} = {}

	local seen = {}

	for _, descendant in ipairs(
		game:GetDescendants()
		) do

		if
			descendant:IsA(
				"LuaSourceContainer"
			)
				and descendant ~= script
				and not seen[descendant]
		then

			if not (
				ignorePackages
					and isInsidePackage(
						descendant
					)
				) then

				seen[descendant] =
					true

				table.insert(
					scripts,
					descendant
				)
			end
		end
	end

	return scripts
end

------------------------------------------------------------
-- GET SCRIPTS FROM CURRENT SELECTION
------------------------------------------------------------

local function getScriptsFromSelection(): {
	LuaSourceContainer
	}

	local scripts: {
		LuaSourceContainer
	} = {}

	local seen = {}

	for _, selectedInstance in ipairs(
		Selection:Get()
		) do

		----------------------------------------------------
		-- Selected object itself.
		----------------------------------------------------

		if
			selectedInstance:IsA(
				"LuaSourceContainer"
			)
				and selectedInstance ~= script
		then

			if not (
				ignorePackages
					and isInsidePackage(
						selectedInstance
					)
				) then

				if not seen[selectedInstance] then

					seen[selectedInstance] =
						true

					table.insert(
						scripts,
						selectedInstance
					)
				end
			end
		end

		----------------------------------------------------
		-- All scripts beneath selected object.
		----------------------------------------------------

		for _, descendant in ipairs(
			selectedInstance:GetDescendants()
			) do

			if
				descendant:IsA(
					"LuaSourceContainer"
				)
					and descendant ~= script
			then

				if not (
					ignorePackages
						and isInsidePackage(
							descendant
						)
					) then

					if not seen[descendant] then

						seen[descendant] =
							true

						table.insert(
							scripts,
							descendant
						)
					end
				end
			end
		end
	end

	return scripts
end

------------------------------------------------------------
-- UPDATE ONE SCRIPT
--
-- The transform executes against UpdateSourceAsync's
-- current oldSource value.
------------------------------------------------------------

local function updateScriptSource(
	targetScript: LuaSourceContainer,
	transform:
		(string) -> (string, number)
): (boolean, number)

	local changedCount =
		0

	local ok, errorMessage =
		pcall(
			function()

				ScriptEditorService:UpdateSourceAsync(
					targetScript,
					function(oldSource)

						local newSource, count =
						transform(
							oldSource
						)

						changedCount =
						count

						if newSource == oldSource
							or count == 0 then

							return oldSource
						end

						return newSource
					end
				)
			end
		)

	if not ok then

		warn(
			"[DebugPrintManager] Failed to update:",
			targetScript:GetFullName(),
			errorMessage
		)

		return false, 0
	end

	return true, changedCount
end

------------------------------------------------------------
-- SCAN SCRIPTS FOR STATISTICS
------------------------------------------------------------

local function scanStatistics(
	scripts: {LuaSourceContainer}
): OperationStats

	local stats:
		OperationStats = {

			scriptsScanned =
			0,

			scriptsChanged =
			0,

			printsAffected =
			0,

			failedScripts =
			0,

			ignoredPackageScripts =
			0,
		}

	for _, targetScript in ipairs(
		scripts
		) do

		if targetScript ~= script then

			stats.scriptsScanned += 1

			local ok, sourceOrError =
				pcall(
					function()

						return ScriptEditorService:GetEditorSource(
							targetScript
						)
					end
				)

			if ok
				and type(sourceOrError) == "string"
			then

				local source =
					sourceOrError

				local activePrints =
					#findStandalonePrintCalls(
						source
					)

				local disabledPrints =
					countDisabledPrintStatements(
						source
					)

				stats.printsAffected +=
					activePrints
					+ disabledPrints

			else

				stats.failedScripts += 1
			end
		end
	end

	return stats
end

------------------------------------------------------------
-- OPERATION STATE
------------------------------------------------------------

local operationInProgress =
	false

------------------------------------------------------------
-- DOCK WIDGET
------------------------------------------------------------

local widgetInfo =
	DockWidgetPluginGuiInfo.new(
		Enum.InitialDockState.Float,
		false,
		false,
		380,
		620,
		300,
		450
	)

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 3 - WIDGET INFO CREATED")

local widget =
	plugin:CreateDockWidgetPluginGuiAsync(
		"DebugPrintManagerWidget",
		widgetInfo
	)

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 4 - WIDGET CREATED")

widget.Title =
	"Debug Print Manager"

------------------------------------------------------------
-- TOOLBAR / WIDGET SYNC
--
-- Connect this immediately after the widget exists so the
-- toolbar button is initialized before the rest of the UI
-- is constructed.
------------------------------------------------------------

toolbarButton.Click:Connect(
	function()

		widget.Enabled =
			not widget.Enabled
	end
)

widget:GetPropertyChangedSignal(
	"Enabled"
):Connect(
	function()

		toolbarButton:SetActive(
			widget.Enabled
		)
	end
)

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 5 - TOOLBAR/WIDGET SYNC CONNECTED")

------------------------------------------------------------
-- INITIAL STATE
------------------------------------------------------------

toolbarButton:SetActive(
	widget.Enabled
)
-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 6 - BEGIN UI CONSTRUCTION")

------------------------------------------------------------
-- UI ROOT
------------------------------------------------------------

local root =
	Instance.new("Frame")

root.Name =
	"Root"

root.Size =
	UDim2.fromScale(
		1,
		1
	)

root.BackgroundColor3 =
	Color3.fromRGB(
		32,
		32,
		32
	)

root.BorderSizePixel =
	0

root.Parent =
	widget

------------------------------------------------------------
-- PADDING
------------------------------------------------------------

local rootPadding =
	Instance.new("UIPadding")

rootPadding.PaddingTop =
	UDim.new(
		0,
		12
	)

rootPadding.PaddingBottom =
	UDim.new(
		0,
		12
	)

rootPadding.PaddingLeft =
	UDim.new(
		0,
		12
	)

rootPadding.PaddingRight =
	UDim.new(
		0,
		12
	)

rootPadding.Parent =
	root

------------------------------------------------------------
-- TITLE
------------------------------------------------------------

local titleLabel =
	Instance.new("TextLabel")

titleLabel.Size =
	UDim2.new(
		1,
		0,
		0,
		32
	)

titleLabel.BackgroundTransparency =
	1

titleLabel.Font =
	Enum.Font.GothamBold

titleLabel.TextSize =
	20

titleLabel.Text =
	"DEBUG PRINT MANAGER"

titleLabel.TextColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

titleLabel.TextXAlignment =
	Enum.TextXAlignment.Left

titleLabel.Parent =
	root

------------------------------------------------------------
-- STATUS
------------------------------------------------------------

local statusLabel =
	Instance.new("TextLabel")

statusLabel.Position =
	UDim2.new(
		0,
		0,
		0,
		40
	)

statusLabel.Size =
	UDim2.new(
		1,
		0,
		0,
		30
	)

statusLabel.BackgroundTransparency =
	1

statusLabel.Font =
	Enum.Font.Gotham

statusLabel.TextSize =
	14

statusLabel.Text =
	"Ready"

statusLabel.TextColor3 =
	Color3.fromRGB(
		180,
		180,
		180
	)

statusLabel.TextXAlignment =
	Enum.TextXAlignment.Left

statusLabel.Parent =
	root

local function setStatus(
	text: string
)

	statusLabel.Text =
		text
end

------------------------------------------------------------
-- HELPER: CREATE UI BUTTON
------------------------------------------------------------

local function createUIActionButton(
	name: string,
	text: string,
	position: UDim2,
	size: UDim2
): TextButton

	local button =
		Instance.new("TextButton")

	button.Name =
		name

	button.Position =
		position

	button.Size =
		size

	button.BackgroundColor3 =
		Color3.fromRGB(
			55,
			55,
			55
		)

	button.BorderSizePixel =
		0

	button.AutoButtonColor =
		true

	button.Font =
		Enum.Font.GothamBold

	button.TextSize =
		14

	button.Text =
		text

	button.TextColor3 =
		Color3.fromRGB(
			255,
			255,
			255
		)

	button.Parent =
		root

	local corner =
		Instance.new("UICorner")

	corner.CornerRadius =
		UDim.new(
			0,
			6
		)

	corner.Parent =
		button

	return button
end

------------------------------------------------------------
-- ACTION BUTTONS
------------------------------------------------------------

local disableAllButton =
	createUIActionButton(
		"DisableAllButton",
		"DISABLE ALL",
		UDim2.new(
			0,
			0,
			0,
			82
		),
		UDim2.new(
			0.48,
			-4,
			0,
			38
		)
	)

local restoreAllButton =
	createUIActionButton(
		"RestoreAllButton",
		"RESTORE ALL",
		UDim2.new(
			0.52,
			4,
			0,
			82
		),
		UDim2.new(
			0.48,
			-4,
			0,
			38
		)
	)

local disableSelectedButton =
	createUIActionButton(
		"DisableSelectedButton",
		"DISABLE SELECTED",
		UDim2.new(
			0,
			0,
			0,
			128
		),
		UDim2.new(
			0.48,
			-4,
			0,
			38
		)
	)

local restoreSelectedButton =
	createUIActionButton(
		"RestoreSelectedButton",
		"RESTORE SELECTED",
		UDim2.new(
			0.52,
			4,
			0,
			128
		),
		UDim2.new(
			0.48,
			-4,
			0,
			38
		)
	)

local enableOnlySelectedButton =
	createUIActionButton(
		"EnableOnlySelectedButton",
		"ENABLE ONLY SELECTED",
		UDim2.new(
			0,
			0,
			0,
			174
		),
		UDim2.new(
			0.48,
			-4,
			0,
			38
		)
	)

local refreshStatsButton =
	createUIActionButton(
		"RefreshStatsButton",
		"REFRESH STATS",
		UDim2.new(
			0.52,
			4,
			0,
			174
		),
		UDim2.new(
			0.48,
			-4,
			0,
			38
		)
	)

------------------------------------------------------------
-- IGNORE PACKAGES
------------------------------------------------------------

local ignorePackagesButton =
	createUIActionButton(
		"IgnorePackagesButton",
		"",
		UDim2.new(
			0,
			0,
			0,
			220
		),
		UDim2.new(
			1,
			0,
			0,
			36
		)
	)

local function updateIgnorePackagesButton()

	ignorePackagesButton.Text =
		if ignorePackages
		then "[✓] IGNORE PACKAGES"
		else "[ ] IGNORE PACKAGES"

end

updateIgnorePackagesButton()

------------------------------------------------------------
-- SEPARATOR
------------------------------------------------------------

local separator =
	Instance.new("Frame")

separator.Position =
	UDim2.new(
		0,
		0,
		0,
		268
	)

separator.Size =
	UDim2.new(
		1,
		0,
		0,
		1
	)

separator.BackgroundColor3 =
	Color3.fromRGB(
		75,
		75,
		75
	)

separator.BorderSizePixel =
	0

separator.Parent =
	root

------------------------------------------------------------
-- STATISTICS TITLE
------------------------------------------------------------

local statisticsTitle =
	Instance.new("TextLabel")

statisticsTitle.Position =
	UDim2.new(
		0,
		0,
		0,
		282
	)

statisticsTitle.Size =
	UDim2.new(
		1,
		0,
		0,
		25
	)

statisticsTitle.BackgroundTransparency =
	1

statisticsTitle.Font =
	Enum.Font.GothamBold

statisticsTitle.TextSize =
	16

statisticsTitle.Text =
	"PLACE STATISTICS"

statisticsTitle.TextColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

statisticsTitle.TextXAlignment =
	Enum.TextXAlignment.Left

statisticsTitle.Parent =
	root

------------------------------------------------------------
-- STATISTICS LABEL
------------------------------------------------------------

local statisticsLabel =
	Instance.new("TextLabel")

statisticsLabel.Position =
	UDim2.new(
		0,
		0,
		0,
		310
	)

statisticsLabel.Size =
	UDim2.new(
		1,
		0,
		0,
		105
	)

statisticsLabel.BackgroundColor3 =
	Color3.fromRGB(
		24,
		24,
		24
	)

statisticsLabel.BorderSizePixel =
	0

statisticsLabel.Font =
	Enum.Font.Code

statisticsLabel.TextSize =
	13

statisticsLabel.TextWrapped =
	true

statisticsLabel.TextXAlignment =
	Enum.TextXAlignment.Left

statisticsLabel.TextYAlignment =
	Enum.TextYAlignment.Top

statisticsLabel.Text =
	"Scripts scanned: 0\n"
	.. "Scripts with prints: 0\n"
	.. "Active prints: 0\n"
	.. "Disabled prints: 0\n"
	.. "Ignored package scripts: 0"

statisticsLabel.TextColor3 =
	Color3.fromRGB(
		210,
		210,
		210
	)

statisticsLabel.Parent =
	root

local statisticsPadding =
	Instance.new("UIPadding")

statisticsPadding.PaddingTop =
	UDim.new(
		0,
		8
	)

statisticsPadding.PaddingBottom =
	UDim.new(
		0,
		8
	)

statisticsPadding.PaddingLeft =
	UDim.new(
		0,
		8
	)

statisticsPadding.PaddingRight =
	UDim.new(
		0,
		8
	)

statisticsPadding.Parent =
	statisticsLabel

------------------------------------------------------------
-- SELECTION TITLE
------------------------------------------------------------

local selectionTitle =
	Instance.new("TextLabel")

selectionTitle.Position =
	UDim2.new(
		0,
		0,
		0,
		430
	)

selectionTitle.Size =
	UDim2.new(
		1,
		0,
		0,
		25
	)

selectionTitle.BackgroundTransparency =
	1

selectionTitle.Font =
	Enum.Font.GothamBold

selectionTitle.TextSize =
	16

selectionTitle.Text =
	"CURRENT SELECTION"

selectionTitle.TextColor3 =
	Color3.fromRGB(
		255,
		255,
		255
	)

selectionTitle.TextXAlignment =
	Enum.TextXAlignment.Left

selectionTitle.Parent =
	root

------------------------------------------------------------
-- SELECTION STATISTICS
------------------------------------------------------------

local selectionLabel =
	Instance.new("TextLabel")

selectionLabel.Position =
	UDim2.new(
		0,
		0,
		0,
		458
	)

selectionLabel.Size =
	UDim2.new(
		1,
		0,
		0,
		90
	)

selectionLabel.BackgroundColor3 =
	Color3.fromRGB(
		24,
		24,
		24
	)

selectionLabel.BorderSizePixel =
	0

selectionLabel.Font =
	Enum.Font.Code

selectionLabel.TextSize =
	13

selectionLabel.TextWrapped =
	true

selectionLabel.TextXAlignment =
	Enum.TextXAlignment.Left

selectionLabel.TextYAlignment =
	Enum.TextYAlignment.Top

selectionLabel.Text =
	"Objects selected: 0\n"
	.. "Scripts affected: 0\n"
	.. "Prints found: 0"

selectionLabel.TextColor3 =
	Color3.fromRGB(
		210,
		210,
		210
	)

selectionLabel.Parent =
	root

local selectionPadding =
	Instance.new("UIPadding")

selectionPadding.PaddingTop =
	UDim.new(
		0,
		8
	)

selectionPadding.PaddingLeft =
	UDim.new(
		0,
		8
	)

selectionPadding.Parent =
	selectionLabel

------------------------------------------------------------
-- SET UI BUTTON STATE
------------------------------------------------------------

local function setActionButtonsEnabled(
	enabled: boolean
)

	disableAllButton.Interactable =
		enabled

	restoreAllButton.Interactable =
		enabled

	disableSelectedButton.Interactable =
		enabled

	restoreSelectedButton.Interactable =
		enabled

	enableOnlySelectedButton.Interactable =
		enabled

	refreshStatsButton.Interactable =
		enabled

	ignorePackagesButton.Interactable =
		enabled
end
------------------------------------------------------------
-- UPDATE PLACE STATISTICS
------------------------------------------------------------

local function updatePlaceStatistics()

	local scripts =
		getScriptsInPlace()

	local stats =
		scanStatistics(
			scripts
		)

	local scriptsWithPrints =
		0

	local activePrints =
		0

	local disabledPrints =
		0

	for _, targetScript in ipairs(
		scripts
		) do

		local ok, sourceOrError =
			pcall(
				function()

					return ScriptEditorService:GetEditorSource(
						targetScript
					)
				end
			)

		if ok
			and type(sourceOrError) == "string"
		then

			local source =
				sourceOrError

			local active =
				#findStandalonePrintCalls(
					source
				)

			local disabled =
				countDisabledPrintStatements(
					source
				)

			activePrints +=
				active

			disabledPrints +=
				disabled

			if active > 0
				or disabled > 0 then

				scriptsWithPrints += 1
			end
		end
	end

	--------------------------------------------------------
	-- Package count is not included in getScriptsInPlace()
	-- while Ignore Packages is enabled.
	--------------------------------------------------------

	local ignoredPackageScripts =
		0

	if ignorePackages then

		for _, descendant in ipairs(
			game:GetDescendants()
			) do

			if
				descendant:IsA(
					"LuaSourceContainer"
				)
					and descendant ~= script
					and isInsidePackage(
						descendant
					)
			then

				ignoredPackageScripts += 1
			end
		end
	end

	statisticsLabel.Text =
		string.format(
			"Scripts scanned: %d\n"
			.. "Scripts with prints: %d\n"
			.. "Active prints: %d\n"
			.. "Disabled prints: %d\n"
			.. "Ignored package scripts: %d",

			stats.scriptsScanned,
			scriptsWithPrints,
			activePrints,
			disabledPrints,
			ignoredPackageScripts
		)

end

------------------------------------------------------------
-- UPDATE SELECTION STATISTICS
------------------------------------------------------------

local function updateSelectionStatistics()

	local selectedObjects =
		Selection:Get()

	local selectedScripts =
		getScriptsFromSelection()

	local activePrints =
		0

	local disabledPrints =
		0

	local scriptsWithPrints =
		0

	local failedScripts =
		0

	for _, targetScript in ipairs(
		selectedScripts
		) do

		local ok, sourceOrError =
			pcall(
				function()

					return ScriptEditorService:GetEditorSource(
						targetScript
					)
				end
			)

		if ok
			and type(sourceOrError) == "string"
		then

			local source =
				sourceOrError

			local active =
				#findStandalonePrintCalls(
					source
				)

			local disabled =
				countDisabledPrintStatements(
					source
				)

			activePrints +=
				active

			disabledPrints +=
				disabled

			if active > 0
				or disabled > 0 then

				scriptsWithPrints += 1
			end

		else

			failedScripts += 1
		end
	end

	selectionLabel.Text =
		string.format(
			"Objects selected: %d\n"
			.. "Scripts affected: %d\n"
			.. "Scripts with prints: %d\n"
			.. "Active prints: %d\n"
			.. "Disabled prints: %d",

			#selectedObjects,
			#selectedScripts,
			scriptsWithPrints,
			activePrints,
			disabledPrints
		)

	if failedScripts > 0 then

		selectionLabel.Text =
			selectionLabel.Text
			.. string.format(
				"\nUnreadable scripts: %d",
				failedScripts
			)
	end
end

------------------------------------------------------------
-- REFRESH ALL STATS
------------------------------------------------------------

local function refreshStatistics()

	setStatus(
		"Scanning scripts..."
	)

	task.spawn(
		function()

			updatePlaceStatistics()
			updateSelectionStatistics()

			setStatus(
				"Statistics updated."
			)
		end
	)
end

------------------------------------------------------------
-- RUN STANDARD OPERATION
------------------------------------------------------------

local function runOperation(
	operationName: string,
	displayName: string,
	transform:
		(string) -> (string, number),
	scriptsOverride:
		{LuaSourceContainer}?
)

	if operationInProgress then

		setStatus(
			"Another operation is already running."
		)

		return
	end

	local scripts =
		scriptsOverride
		or getScriptsInPlace()

	if #scripts == 0 then

		setStatus(
			"No eligible scripts found."
		)

		updateSelectionStatistics()

		return
	end

	local recording =
		ChangeHistoryService:TryBeginRecording(
			operationName,
			displayName
		)

	if not recording then

		setStatus(
			"Could not start Studio history recording."
		)

		return
	end

	operationInProgress =
		true

	setActionButtonsEnabled(
		false
	)

	setStatus(
		"Working..."
	)

	local changedScripts =
		0

	local changedPrints =
		0

	local failedScripts =
		0

	local operationSucceeded,
		operationError =
		pcall(
			function()

				for _, targetScript in ipairs(
					scripts
					) do

					local success, count =
					updateScriptSource(
						targetScript,
						transform
					)

					if not success then

						failedScripts += 1

					elseif count > 0 then

						changedScripts += 1
						changedPrints += count
					end
				end
			end
		)

	if operationSucceeded then

		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Commit
		)

		if failedScripts > 0 then

			setStatus(
				string.format(
					"%s  |  %d scripts changed, %d prints affected, %d failed.",
					displayName,
					changedScripts,
					changedPrints,
					failedScripts
				)
			)

		else

			setStatus(
				string.format(
					"%s  |  %d scripts changed, %d prints affected.",
					displayName,
					changedScripts,
					changedPrints
				)
			)
		end

	else

		warn(
			"[DebugPrintManager] Operation failed:",
			operationError
		)

		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Cancel
		)

		setStatus(
			"Operation failed. Changes were cancelled."
		)
	end

	operationInProgress =
		false

	setActionButtonsEnabled(
		true
	)

	updatePlaceStatistics()
	updateSelectionStatistics()
end

------------------------------------------------------------
-- ENABLE ONLY SELECTED
------------------------------------------------------------

local function runEnableOnlySelected()

	if operationInProgress then

		setStatus(
			"Another operation is already running."
		)

		return
	end

	local selectedScripts =
		getScriptsFromSelection()

	if #selectedScripts == 0 then

		setStatus(
			"No eligible scripts found in the selection."
		)

		return
	end

	local allScripts =
		getScriptsInPlace()

	if #allScripts == 0 then

		setStatus(
			"No eligible scripts found in the place."
		)

		return
	end

	local selectedSet:
		{[LuaSourceContainer]: boolean} =
		{}

	for _, targetScript in ipairs(
		selectedScripts
		) do

		selectedSet[targetScript] =
			true
	end

	local recording =
		ChangeHistoryService:TryBeginRecording(
			"EnableOnlySelectedDebugPrints",
			"Enabled debug prints only in selected scripts."
		)

	if not recording then

		setStatus(
			"Could not start Studio history recording."
		)

		return
	end

	operationInProgress =
		true

	setActionButtonsEnabled(
		false
	)

	setStatus(
		"Enabling prints only in selection..."
	)

	local changedScripts =
		0

	local changedPrints =
		0

	local failedScripts =
		0

	local operationSucceeded,
		operationError =
		pcall(
			function()

				for _, targetScript in ipairs(
					allScripts
					) do

					local transform

					if selectedSet[targetScript] then

						transform =
						restorePrintsInSource

					else

						transform =
						disablePrintsInSource
					end

					local success, count =
					updateScriptSource(
						targetScript,
						transform
					)

					if not success then

						failedScripts += 1

					elseif count > 0 then

						changedScripts += 1
						changedPrints += count
					end
				end
			end
		)

	if operationSucceeded then

		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Commit
		)

		setStatus(
			string.format(
				"Selection only enabled  |  %d scripts changed, %d prints affected.",
				changedScripts,
				changedPrints
			)
		)

		if failedScripts > 0 then

			setStatus(
				string.format(
					"Selection only enabled  |  %d changed, %d prints, %d failed.",
					changedScripts,
					changedPrints,
					failedScripts
				)
			)
		end

	else

		warn(
			"[DebugPrintManager] Enable Only Selected failed:",
			operationError
		)

		ChangeHistoryService:FinishRecording(
			recording,
			Enum.FinishRecordingOperation.Cancel
		)

		setStatus(
			"Enable Only Selected failed. Changes were cancelled."
		)
	end

	operationInProgress =
		false

	setActionButtonsEnabled(
		true
	)

	updatePlaceStatistics()
	updateSelectionStatistics()
end

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 7 - UI CONSTRUCTION COMPLETE")

------------------------------------------------------------
-- DISABLE ALL
------------------------------------------------------------

disableAllButton.Activated:Connect(
	function()

		runOperation(
			"DisableDebugPrints",
			"Disabled all debug print statements.",
			disablePrintsInSource
		)
	end
)

------------------------------------------------------------
-- RESTORE ALL
------------------------------------------------------------

restoreAllButton.Activated:Connect(
	function()

		runOperation(
			"RestoreDebugPrints",
			"Restored all plugin-disabled print statements.",
			restorePrintsInSource
		)
	end
)

------------------------------------------------------------
-- DISABLE SELECTED
------------------------------------------------------------

disableSelectedButton.Activated:Connect(
	function()

		local selectedScripts =
			getScriptsFromSelection()

		runOperation(
			"DisableSelectedDebugPrints",
			"Disabled debug prints in selected scripts.",
			disablePrintsInSource,
			selectedScripts
		)
	end
)

------------------------------------------------------------
-- RESTORE SELECTED
------------------------------------------------------------

restoreSelectedButton.Activated:Connect(
	function()

		local selectedScripts =
			getScriptsFromSelection()

		runOperation(
			"RestoreSelectedDebugPrints",
			"Restored debug prints in selected scripts.",
			restorePrintsInSource,
			selectedScripts
		)
	end
)

------------------------------------------------------------
-- ENABLE ONLY SELECTED
------------------------------------------------------------

enableOnlySelectedButton.Activated:Connect(
	function()

		runEnableOnlySelected()
	end
)

------------------------------------------------------------
-- REFRESH STATISTICS
------------------------------------------------------------

refreshStatsButton.Activated:Connect(
	function()

		refreshStatistics()
	end
)

------------------------------------------------------------
-- TOGGLE IGNORE PACKAGES
------------------------------------------------------------

ignorePackagesButton.Activated:Connect(
	function()

		if operationInProgress then

			return
		end

		ignorePackages =
			not ignorePackages

		plugin:SetSetting(
			IGNORE_PACKAGES_SETTING,
			ignorePackages
		)

		updateIgnorePackagesButton()

		if ignorePackages then

			setStatus(
				"Package scripts are now ignored."
			)

		else

			setStatus(
				"Package scripts are now included."
			)
		end

		refreshStatistics()
	end
)

------------------------------------------------------------
-- SELECTION CHANGED
------------------------------------------------------------

Selection.SelectionChanged:Connect(
	function()

		if operationInProgress then

			return
		end

		updateSelectionStatistics()
	end
)

-- [DEBUG_PRINT_MANAGER_DISABLED] print("[DebugPrintManager] STEP 8 - PLUGIN READY")
