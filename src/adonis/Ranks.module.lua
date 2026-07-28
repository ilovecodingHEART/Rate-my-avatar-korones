-------------------------------
-- Scroll down for settings  --
-------------------------------

--[[
	How to add administrators:
		Below are the administrator permission levels/ranks (Mods, Admins, HeadAdmins, Creators, StuffYouAdd, etc)
		Simply place users into the respective "Users" table for whatever level/rank you want to give them.

		Format example:

			Ranks = {
				["Moderators"] = {
					Level = 100;
					Users = {
						"Username"; -- Example: "roblox"
						"Username:UserId"; -- Example: "roblox:1"
						UserId; -- Example: 1
						"Group:GroupId:GroupRank"; -- Example: "Group:123456:50"
						"Group:GroupId"; -- Example: "Group:123456"
						"Item:ItemID"; -- Example: "Item:123456"
						"GamePass:GamePassID"; -- Example: "GamePass:123456"
						"Subscription:SubscriptionId"; -- Example: "Subscription:123456"
					}
				}
			}

		If you use custom ranks, existing custom ranks will be imported with a level of 1.
		Add all new CustomRanks to the table below with the respective level you want them to be.

	NOTE: Changing the level of built-in ranks (Moderators, Admins, HeadAdmins, Creators)
	will also change the permission level for any built-in commands associated with that rank.
--]]

--------------------
-- RANKS SETTINGS --
--------------------

return {
	Ranks = {
		["Moderators"] = {
			Level = 100;
			Users = {
				-- Mods are whitelisted in game through the booth admin panel,
				-- not here, because that list lives in a DataStore and can
				-- change mid session. Anyone made a Mod there is a Mod there;
				-- this rank stays empty on purpose.
			};
		};

		["Admins"] = {
			Level = 200;
			Users = {
				-- Same as above: granted from the booth panel by a Developer.
			};
		};

		["HeadAdmins"] = {
			Level = 300;
			Users = {
				-- Developers. Hard coded in ServerScriptService.Server, so
				-- hard coded here too - the two have to agree.
				"qzc:78857";
				"ywinfe:181869";
			};
		};

		["Creators"] = {
			Level = 900; -- Anything 900 or higher will be considered a creator and will bypass all perms & be allowed to edit settings in-game.
			Users = {
				-- Owner.
				"thugshaker:49603";
			};
		};
	};
};