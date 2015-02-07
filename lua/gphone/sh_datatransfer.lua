----// Shared Net Messages for "gPhone_DataTransfer" //----


if SERVER then
	--// Receives data from applications and runs it on the server
	local antiSpamWindow, lastText = 0, 0
	net.Receive( "gPhone_DataTransfer", function( len, ply )
		local data = net.ReadTable()
		local header = data.header
		
		hook.Run( "gPhone_ReceivedClientData", ply, header, data )
		
		if header == GPHONE_MONEY_TRANSFER then -- Money transaction
			local amount = tonumber(data.amount)
			local target = data.target
			local plyWallet = tonumber(ply:getDarkRPVar("money"))
			
			-- Cooldowns to prevent spam
			if ply:getTransferCooldown() > 0 then
				gPhone.chatMsg( ply, "You must wait "..math.Round(ply:getTransferCooldown()).."s before sending more money" )
				return
			end
			
			-- If the player disconnected or they are sending money to themselves, stop the transaction
			if not IsValid(target) or target == ply then
				gPhone.chatMsg( ply, "Unable to complete transaction - invalid recipient" )
				return
			end
			
			-- If a negative or string amount got through, stop it
			if amount < 0 or amount == nil then 
				gPhone.chatMsg( ply, "Unable to complete transaction - nil amount" )
				return
			else
				-- Force the amount to be positive. If a negative value is passed then the 'exploiter' will still transfer the cash 
				amount = math.abs(amount) 
			end
			
			-- Make sure the player has this money and didn't cheat it on the client
			if plyWallet > amount then 	
				-- Last measure before allowing the deal, call the hook
				local shouldTransfer, denyReason = hook.Run( "gPhone_ShouldAllowTransaction", ply, target, amount )
				if shouldTransfer == false then
					if denyReason != nil then
						gPhone.chatMsg( ply, denyReason )
					else
						gPhone.chatMsg( ply, "Unable to complete transaction, sorry" )
					end
					return
				end
				
				-- Complete the transaction
				target:addMoney(amount)
				ply:addMoney(-amount)
				gPhone.chatMsg( target, "Received $"..amount.." from "..ply:Nick().."!" )
				gPhone.chatMsg( ply, "Wired $"..amount.." to "..target:Nick().." successfully!" )
				gPhone.confirmTransaction( ply, {target=target:Nick(), amount=amount, time=os.date( "%x - %I:%M%p")} )
				
				ply:setTransferCooldown( 5 )
			else	
				gPhone.msgC( GPHONE_MSGC_WARNING, ply:Nick().." attempted to force a transaction with more money than they had!" )
				gPhone.chatMsg( ply, "Unable to complete transaction - lack of funds" )
				return
			end
		elseif header == GPHONE_REQUEST_TEXTS then
			
		elseif header == GPHONE_TEXT_MSG then
			local canText = ply:GetNWBool("gPhone_CanText", true)
			local msgTable = {}
			local nick = data.tbl.target
			local target = util.getPlayerByNick( nick )
			
			msgTable = data.tbl
			msgTable.sender = ply:Nick()
			msgTable.self = false
			
			-- Flagged for spam
			if not canText then
				gPhone.chatMsg( ply, "You cannot text for "..math.Round(ply.TextCooldown).." more seconds!" )
				return 
			end
			
			-- Anti text spam
			ply.MessageCount = (ply.MessageCount or 0) + 1
			hook.Add("Think", "gPhone_AntiSpam_"..ply:SteamID(), function()
				-- Span of time in which texts are counted to check against spam
				if CurTime() > antiSpamWindow then
					antiSpamWindow = CurTime() + gPhone.config.antiSpamTimeframe
					ply.MessageCount = 0
				end
				
				-- If they haven't texted in 10 seconds, this hook is no longer needed
				if CurTime() - lastText > 10 then
					hook.Remove("Think", "gPhone_AntiSpam_"..ply:SteamID())
					ply.MessageCount = 0
				end

				-- Caught em
				if ply.MessageCount > gPhone.config.textPerTimeframeLimit and CurTime() < antiSpamWindow then
					ply:SetNWBool("gPhone_CanText", false)
					ply.TextCooldown = gPhone.config.textSpamCooldown
					
					gPhone.msgC( GPHONE_MSGC_WARNING, ply:Nick().." has been caught spamming the texting system" )
					gPhone.chatMsg( ply, "To prevent spam, you have been blocked from texting for "..ply.TextCooldown.." seconds!" )
					ply.MessageCount = 0 
					
					-- Countdown until the cooldown ends
					local endTime = CurTime() + ply.TextCooldown
					hook.Add("Think", "gPhone_TextCooldown_"..ply:SteamID(), function()
						ply.TextCooldown = endTime - CurTime()
						
						if ply.TextCooldown <= 0 then
							ply.TextCooldown = nil
							canText = true
							ply:SetNWBool("gPhone_CanText", true)
							hook.Remove("Think", "gPhone_TextCooldown_"..ply:SteamID())
						end
					end)
				end
			end)
			
			-- Send the message the the target
			net.Start("gPhone_DataTransfer")
				net.WriteTable( {header=GPHONE_TEXT_MSG, data=msgTable} )
			net.Send( target )
			
			lastText = CurTime()
		elseif header == GPHONE_STATE_CHANGED then -- The phone has been opened or closed
			local phoneOpen = data.open
			if phoneOpen == true then
				ply:SetNWBool("gPhone_Open", true)
				hook.Run( "gPhone_Built", ply )
			else
				ply:SetNWBool("gPhone_Open", false)
			end
		elseif header == GPHONE_CUR_APP then
			ply:SetNWString("gPhone_CurApp", data.app)
		elseif header == GPHONE_NET_REQUEST then
			gPhone.receiveRequest( data )
		elseif header == GPHONE_NET_RESPONSE then
			gPhone.receiveResponse( data )
		elseif header == GPHONE_START_CALL then
			local targetNum = data.number
			local callingNum = ply:getPhoneNumber()
			
			local targetPly = gPhone.getPlayerByNumber( targetNum )
			
			print("Calling", targetNum, callingNum)
			local reqStr = ply:Nick().." is calling you"
			gPhone.sendRequest( {sender=ply, app="Phone", msg=reqStr}, targetPly )
		end
	end)
end


if CLIENT then

	--// Receives a Server-side net message
	net.Receive( "gPhone_DataTransfer", function( len, ply )
		local data = net.ReadTable()
		local header = data.header
		
		
		if header == GPHONE_BUILD then
			gPhone.buildPhone()
		elseif header == GPHONE_RETURNAPP then
			local name, active = nil, gPhone.getActiveApp() 
			active = active or {}
			active.Data = active.Data or {}
			
			if active.Data.PrintName then
				name = active.Data.PrintName or nil
			end

			net.Start("gPhone_DataTransfer")
				net.WriteTable( {header=GPHONE_RETURNAPP, app=name} )
			net.SendToServer()
		elseif header == GPHONE_RUN_APPFUNC then
			local app = data.app
			local func = data.func
			local args = data.args
			
			if gApp[app:lower()] then
				app = app:lower()
				for k, v in pairs( gApp[app].Data ) do
					if k:lower() == func:lower() then
						gApp[app].Data[k]( unpack(args) )
						return
					end
				end
			end
			gPhone.msgC( GPHONE_MSGC_WARNING, "Unknown application ("..app..") function "..func.."!" )
		elseif header == GPHONE_RUN_FUNC then
			local func = data.func
			local args = data.args
			
			for k, v in pairs(gPhone) do
				if k:lower() == func:lower() then
					gPhone[k]( unpack(args) )
					return
				end
			end
			
			gPhone.msgC( GPHONE_MSGC_WARNING, "Unable phone function "..func.."!")
		elseif header == GPHONE_MONEY_CONFIRMED then
			local writeTable = {}
			data.header = nil
			data = data[1]
			
			--[[
				Problemo:
			On Client - ALL transactions for any server will show up
			On Server - Server gets flooded with tons of .txt documents that might only contain 1 transaction
			
			No limit on logs
			]]
			
			if file.Exists( "gphone/appdata/t_log.txt", "DATA" ) then
				local readFile = file.Read( "gphone/appdata/t_log.txt", "DATA" )
				print("File exists", readFile)
				local readTable = util.JSONToTable( gPhone.unscrambleJSON( readFile ) ) 
				
				--table.Add( tbl, readTable )
				writeTable = readTable
				
				--local key = #writeTable+1
				table.insert( writeTable, 1, {amount=data.amount, target=data.target, time=data.time} )
				--writeTable[key] = {amount=data.amount, target=data.target, time=data.time}
				gPhone.msgC( GPHONE_MSGC_NONE, "Appending new transaction log into table")
			else
				gPhone.msgC( GPHONE_MSGC_WARNING, "No transaction file, creating one...")
				writeTable[1] = {amount=data.amount, target=data.target, time=data.time}
				
				PrintTable(writeTable)
			end
			
			local json = util.TableToJSON( writeTable )
			json = gPhone.scrambleJSON( json )
		
			file.CreateDir( "gphone" )
			file.Write( "gphone/appdata/t_log.txt", json)
		elseif header == GPHONE_TEXT_MSG then
			gPhone.receiveTextMessage( data.data )
		elseif header == GPHONE_NET_REQUEST then
			gPhone.receiveRequest( data )
		elseif header == GPHONE_NET_RESPONSE then
			gPhone.receiveResponse( data )
		end
	end)

end