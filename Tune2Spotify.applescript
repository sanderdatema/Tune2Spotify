(*
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)

------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
-- Search Spotify in iTunes
--
-- By Sander Datema (sanderdatema@gmail.com)
--
-- Purpose: put songs in iTunes playlists based on whether they are in Spotify or not
--
--
-- If you like this script, please consider buying me a beer or coffee: http://j.mp/c8veE2
-- A lot of time went into these 500+ lines of code, so I'd appreciate it. Thanks!
--
-- Found bugs? Have a request, etc.? Here please: http://j.mp/bEyTxM
--
------------------------------------------------------------------------------------------------------------------
-- Note: this script depends on XML Tools by Late Night Software: http://j.mp/d9JvNR. Download it from there.
------------------------------------------------------------------------------------------------------------------
--
-- Please edit the options below to your needs.
------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------

-- Fuzzy search, set false to not include the album in the search
property useAlbumInSearch : true

-- Country, in case of trouble
property forceCountry : "NL"

-- Skip checking for duplicates in the end?
property skipDuplicateCheck : true

------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
-- Nothing to edit after this line.
------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------

-- File containing the Spotify links
global spotifyLinkFile

-- Country of the user
global countryToCheck

-- Spotify's search API url
property spotifySearchUrl : "http://ws.spotify.com/search/1/track?q="

-- Names of the playlists we'll use in iTunes
property oneMatchPlaylist : "1. One match"
property multipleMatchPlaylist : "2. Multiple matches"
property noMatchPlaylist : "3. No match"

-- Names of searchMode buttons
property buttonSpotify : "Spotify links"
property buttonPlaylists : "iTunes playlists"
property buttonBoth : "Both"

-- Preparing these 3 variables as lists
global oneMatchList
global multipleMatchList
global noMatchList

-- Make Spotify file, playlists in iTunes or both?
global searchMode

-- DEBUG
property debugging : true -- no logging when set to false

try
	my main()
on error errorTxt
	display dialog "Something went wrong: " & errorTxt & " Please report to sanderdatema@gmail.com" buttons {"OK"}
end try



------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
-- Methods
------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------

-- The main routine
on main()
	-- First a few checks. If it fails, the script will end.
	startupCheck()
	
	-- Now lookup every song in the playlist on Spotify, or use the selection in iTunes
	lookupSongs(getSelection())
	
	-- Remove any duplicates from the three playlists
	if skipDuplicateCheck is false then
		if searchMode is buttonBoth or searchMode is buttonPlaylists then
			removeDuplicateTracksFromPlaylist(oneMatchPlaylist)
			removeDuplicateTracksFromPlaylist(multipleMatchPlaylist)
			removeDuplicateTracksFromPlaylist(noMatchPlaylist)
		end if
	end if
	
	-- If you like the script, please donate!
	showDonateDialog()
	
end main

-- If this check fails, the script will end.
on startupCheck()
	-- Check if iTunes is running
	tell application "Finder"
		if (name of every process) does not contain "iTunes" then
			display dialog "iTunes is not running. Please start it before running this script." buttons {"OK"}
			my exitScript()
		end if
	end tell
	
	-- Make Spotify link list, add songs to playlists in iTunes or both?
	set searchMode to showChoiceDialog()
	
	-- Find which country we are in
	if forceCountry is not false then
		set countryToCheck to forceCountry
	else
		set countryToCheck to getCountryFromIP()
	end if
	
	-- To add the Spotify links to a file, make the new file first
	if searchMode is buttonBoth or searchMode is buttonSpotify then
		my createSpotifyLinkListFile()
	end if
	
	-- Create (if needed) the special playlists in iTunes
	if searchMode is buttonBoth or searchMode is buttonPlaylists then
		my createiTunesPlaylists()
	end if
end startupCheck

-- Lookup songs in Spotify from given selection of songs
on lookupSongs(trackList)
	tell application "iTunes"
		-- Preserve indexing (in case of smart playlists that change)
		set originalIndex to fixed indexing
		set fixed indexing to true
		
		
		-- Go through every single song
		repeat with thisTrack in trackList
			-- set trackFile to file track thisTrack
			-- if trackFile's location is not missing value then
			-- Constructing search query
			-- If fuzzy search is selected we need to remove some data in the search query
			set songAlbum to thisTrack's album
			
			set searchQuery to my createSearchQuery(thisTrack's name, thisTrack's artist, thisTrack's album)
			
			set spotifySearchResult to my searchSong(searchQuery)
			if spotifySearchResult is not false then -- if false, then an error occured.
				if searchMode is buttonBoth or searchMode is buttonPlaylists then
					if (count of spotifySearchResult) is 1 then -- One match found in Spotify
						duplicate thisTrack to playlist oneMatchPlaylist
					else if (count of spotifySearchResult) > 1 then -- Two or more matches found in Spotify
						duplicate thisTrack to playlist multipleMatchPlaylist
					else -- No match found
						duplicate thisTrack to playlist noMatchPlaylist
					end if
				end if
				if searchMode is buttonBoth or searchMode is buttonSpotify then
					my addSpotifyLinksToFile(spotifySearchResult)
				end if
			else
				-- Just skip this song
				my logEvent("\"" & thisTrack's name & "\" was skipped. Error?")
			end if
			-- end if
		end repeat
		
		-- Put indexing back to what it was
		set fixed indexing to originalIndex
	end tell
end lookupSongs

-- Construct the search query
on createSearchQuery(songTrack, songArtist, songAlbum)
	set unwantedCharacters to {"[", "]", "'", "&", "{", "}", "!", "@", "$", "#", "%", "?", "/", "\"", "++", "-"}
	
	-- Remove unwanted characters
	set songTrack to removeCharacters(unwantedCharacters, songTrack)
	set songArtist to removeCharacters(unwantedCharacters, songArtist)
	set songAlbum to removeCharacters(unwantedCharacters, songAlbum)
	
	-- Replace spaces with plus signs
	set songTrack to replaceText(" ", "+", songTrack)
	set songArtist to replaceText(" ", "+", songArtist)
	set songAlbum to replaceText(" ", "+", songAlbum)
	
	-- Now combine the items into one query
	set searchQuery to "track:" & songTrack
	set searchQuery to searchQuery & "+artist:" & songArtist
	-- Should we use the Album in the search?
	if useAlbumInSearch is true then set searchQuery to searchQuery & "+album:" & songAlbum
	
	return searchQuery
end createSearchQuery

-- Add the Spotify links to a file
on addSpotifyLinksToFile(songData)
	if (count of songData) < 1 then return
	set songSpotifyLink to item 1 of songData
	my logEvent("Adding Spotify link \"" & songSpotifyLink & "\" to file")
	do shell script "echo " & songSpotifyLink & " >> " & spotifyLinkFile
end addSpotifyLinksToFile

-- Search Spotify for the given words
on searchSong(searchQuery)
	set searchUrl to spotifySearchUrl & searchQuery
	my logEvent("Search url is \"" & searchUrl & "\"")
	
	-- Use curl to fetch the xml results from Spotify's metadata API
	set xmlResult to do shell script "curl " & quoted form of searchUrl
	
	if xmlResult is "" then -- No XML was returned!
		logEvent("xmlResult was empty, returning")
		return false
	end if
	
	-- Use the XML Tools by Late Night Software
	try
		set xmlResult to parse XML xmlResult
	on error errTxt
		logEvent("Error in XML parsing")
		return false
	end try
	my logEvent("Parsing XML")
	
	-- How many results did we get?
	set resultCount to getElementValue(getAnElement(xmlResult, "totalResults")) as number
	
	logEvent("Results found: " & resultCount)
	if resultCount = 0 then return {} -- Code for "no match found"
	
	-- Check if track is available in selected country
	set trackData to getAnElement(xmlResult, "track")
	set albumData to getAnElement(trackData, "album")
	set availabilityData to getAnElement(albumData, "availability")
	set countryList to splitText(" ", getElementValue(getAnElement(availabilityData, "territories")))
	
	my logEvent("Check for country \"" & makeUPPER(countryToCheck) & "\"")
	if countryList does not contain makeUPPER(countryToCheck) then
		logEvent("Country not found, returning")
		return {} -- No match in selected country
	end if
	
	if resultCount = 1 then -- Found one match
		set searchResult to {getSpotifyLink(trackData)}
		return searchResult
	else if resultCount > 1 then -- Multiple matches found
		set searchResult to {}
		set trackList to my getElements(xmlResult, "track")
		
		-- Sort songs by popularity
		repeat with trackData in trackList
			set itemPopularity to getElementValue(getAnElement(trackData, "popularity"))
			set itemSpotifyLink to getSpotifyLink(trackData)
			my logEvent("Processing: \"" & itemPopularity & ";" & itemSpotifyLink & "\"")
			set end of searchResult to itemPopularity & ";" & itemSpotifyLink
		end repeat
		
		set searchResult to sortListDESC(searchResult)
		
		-- Remove the popularity data from the list
		my logEvent("Sorting done, now removing popularity data from tracks")
		set newSearchResult to {}
		repeat with searchItem in searchResult
			set searchItem to splitText(";", searchItem)
			set itemSpotifyLink to item 2 of searchItem
			set end of newSearchResult to itemSpotifyLink
		end repeat
		
		return newSearchResult
	end if
end searchSong

-- Convert given string to a list
on splitText(delimiter, someText)
	set prevTIDs to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiter
	set output to text items of someText
	set AppleScript's text item delimiters to prevTIDs
	return output
end splitText

-- Convert given list to a string
on joinList(delimiter, someList)
	set prevTIDs to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiter
	set output to "" & someList
	set AppleScript's text item delimiters to prevTIDs
	return output
end joinList

-- Find and return a particular element (this presumes there is only one instance of the element)
on getAnElement(theXML, theElementName)
	repeat with anElement in XML contents of theXML
		if class of anElement is XML element and XML tag of anElement is theElementName then
			return contents of anElement
		end if
	end repeat
	
	return missing value
end getAnElement

-- Return the value of an element
on getElementValue(theXML)
	if theXML is missing value or theXML is {} then
		return ""
	else if class of theXML is string then
		return theXML
	else
		try
			return item 1 of XML contents of theXML
		on error number -1728
			return ""
		end try
	end if
end getElementValue

-- Get the Spotify link of a Spotify song
on getSpotifyLink(trackXML)
	try
		return href of XML attributes of trackXML
	on error number -1728
		return ""
	end try
end getSpotifyLink

-- Find and return all instances of a particular element
on getElements(theXML, theElementName)
	local theResult
	
	set theResult to {}
	repeat with anElement in XML contents of theXML
		if class of anElement is XML element and XML tag of anElement is theElementName then
			set end of theResult to contents of anElement
		end if
	end repeat
	
	return theResult as list
end getElements

-- From Julio (http://j.mp/9oV4Ta)
on removeItemsFromList(itemsToDelete, theList)
	set newList to {}
	
	repeat with i from 1 to count theList
		if {theList's item i} is not in itemsToDelete then set newList's end to theList's item i
	end repeat
	
	return newList
end removeItemsFromList

-- From Bruce Phillips (http://j.mp/cYKIZ0)
on replaceText(find, replace, subject)
	set prevTIDs to text item delimiters of AppleScript
	set text item delimiters of AppleScript to find
	set subject to text items of subject
	
	set text item delimiters of AppleScript to replace
	set subject to "" & subject
	set text item delimiters of AppleScript to prevTIDs
	
	return subject
end replaceText

-- Strip given character from given string
on removeCharacters(theCharacters, theString)
	repeat with theCharacter in theCharacters
		set theString to my replaceText(theCharacter, "", theString)
	end repeat
	
	return theString
end removeCharacters

-- Exit the script as if the user cancelled it
on exitScript()
	error number -128
end exitScript

-- Sort ascending
on sortListASC(theList)
	return sortList(theList, true)
end sortListASC

-- Sort descending
on sortListDESC(theList)
	return sortList(theList, false)
end sortListDESC

-- Sort the given list either ascending or descending
-- From Eric Caterman (http://j.mp/9XUJtA)
on sortList(theList, ascending)
	set old_delims to AppleScript's text item delimiters
	set AppleScript's text item delimiters to {ASCII character 10} -- Always a linefeed
	set listString to (theList as string)
	if ascending is true then
		set sortCommand to " | sort -f"
	else
		set sortCommand to " | sort -f -r"
	end if
	set newString to do shell script "echo " & quoted form of listString & sortCommand
	set newList to (paragraphs of newString)
	set AppleScript's text item delimiters to old_delims
	return newList
end sortList

-- Show the dialog asking people to donate
on showDonateDialog()
	if readPreference("hasDonated") is "yes" then return
	tell application "iTunes"
		set question to display dialog "If you like this Spot-in-iTunes script, please consider buying me a beer or a coffee. I'd appreciate that!" buttons {"Yeah, why not?", "I don't like this script", "I already donated"} default button 1
		set answer to button returned of question
	end tell
	if answer is equal to "Yeah, why not?" then
		open location "http://j.mp/c8veE2"
	else if answer is equal to "I already donated" then
		savePreference("hasDonated", "yes")
	end if
end showDonateDialog

-- Write a line of text to a log file
-- From leenoble_uk (http://j.mp/b1CmVH)
on logEvent(themessage)
	if debugging is false then return
	set themessage to my removeCharacters({"[", "]", "'", "{", "}", "!", "@", "$", "#", "%", "(", ")", "`"}, themessage)
	set theLine to (do shell script "date  +'%Y-%m-%d %H:%M:%S'" as string) & " " & themessage
	do shell script "echo " & theLine & " >> ~/Library/Logs/AppleScript-events.log"
end logEvent

-- From Mimsy (http://j.mp/a5U0TJ)
on getSelection()
	tell application "iTunes"
		-- If some tracks are selected, use only those tracks
		-- Otherwise, use all tracks in the selected playlist
		if selection is {} then
			copy view of front window to selectedLibrary
			copy every track of selectedLibrary to selectedTracks
		else
			copy selection to selectedTracks
		end if
		if (count of selectedTracks) is 0 then
			display dialog "You have nothing selected. Nothing to do." buttons {"OK"}
			my exitScript()
		else
			return selectedTracks
		end if
	end tell
end getSelection

-- Create the file with a list of Spotify links
on createSpotifyLinkListFile()
	set dateString to (do shell script "date +%s") as string
	set spotifyLinkFile to "~/Desktop/Tune2Spotify-" & dateString & ".txt"
end createSpotifyLinkListFile

-- From Kevin Bradley (http://j.mp/assMpB)
-- Change case of given text to lower case
on makelower(theText)
	set newText to ""
	--loop through the letters
	repeat with loop from 1 to (length of theText)
		--convert them to lower case
		set newText to newText & lower(character loop of theText)
	end repeat
	--return the new text
	return newText
end makelower

-- Change case of given letter to lower case
on lower(aLetter)
	--see if the letter is in list of upper case letters
	considering case
		set myChar to offset of aLetter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		--if so, then return the lower case version
		if myChar > 0 then
			return character myChar of "abcdefghijklmnopqrstuvwxyz"
		else
			--else return the original character (it might be a number!)
			return aLetter
		end if
	end considering
end lower

-- Change case of given text to upper case
on makeUPPER(theText)
	set newText to ""
	--loop through the letters
	repeat with loop from 1 to (length of theText)
		--convert them to lower case
		set newText to newText & upper(character loop of theText)
	end repeat
	--return the new text
	return newText
end makeUPPER

-- Change case of given letter to upper case
on upper(aLetter)
	--see if the letter is in list of lower case letters
	considering case
		set myChar to offset of aLetter in "abcdefghijklmnopqrstuvwxyz"
		--if so, then return the upper case version
		if myChar > 0 then
			return character myChar of "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		else
			--else return the original character (it might be a number!)
			return aLetter
		end if
	end considering
end upper

-- Find out in which country the user resides by using the IP address
on getCountryFromIP()
	-- Get IP address of client
	set ipAddress to do shell script "curl ifconfig.me"
	
	if length of ipAddress is 0 then
		return false
	end if
	
	set searchUrl to "http://api.hostip.info/?ip=" & ipAddress
	set xmlResult to do shell script "curl " & quoted form of searchUrl
	
	if xmlResult is "" then -- No XML was returned!
		return false
	end if
	
	-- Use the XML Tools by Late Night Software
	set xmlResult to parse XML xmlResult
	
	-- Check if track is available in selected country
	set featureData to getAnElement(xmlResult, "featureMember")
	set hostIPData to getAnElement(featureData, "Hostip")
	set country to getElementValue(getAnElement(hostIPData, "countryAbbrev"))
	
	if country is "" then
		return false
	end if
	
	my logEvent("Country to use when searching Spotify: " & country)
	return country
end getCountryFromIP

-- Simply create the three playlists this script uses in iTunes
on createiTunesPlaylists()
	createiTunesPlaylist(oneMatchPlaylist, "Tune2Spotify")
	createiTunesPlaylist(multipleMatchPlaylist, "Tune2Spotify")
	createiTunesPlaylist(noMatchPlaylist, "Tune2Spotify")
end createiTunesPlaylists

-- Create a playlist in iTunes if it not already exists
on createiTunesPlaylist(playlistName, folderName)
	tell application "iTunes"
		if exists playlist playlistName then
			return
		else
			if length of folderName > 0 then
				createiTunesFolder(folderName)
				make new user playlist at (folder playlist folderName) with properties {name:playlistName}
			else
				make new user playlist with properties {name:playlistName}
			end if
		end if
	end tell
end createiTunesPlaylist

-- Create a folder in iTunes if it not already exists
on createiTunesFolder(folderName)
	tell application "iTunes"
		if not (exists folder playlist folderName) then
			make new folder playlist with properties {name:folderName}
		end if
	end tell
end createiTunesFolder

-- Save a value to the given preference
on savePreference(prefName, prefValue)
	do shell script "defaults write com.sanderdatema.tune2spotify " & prefName & " " & prefValue
end savePreference

-- Read a value from the given preference
on readPreference(prefName)
	try
		return do shell script "defaults read com.sanderdatema.tune2spotify " & prefName
	on error errTxt
		return false
	end try
end readPreference

-- Remove duplicate tracks. Based on Doug's Applescript. http://j.mp/hZp8sR
on removeDuplicateTracksFromPlaylist(selectedPlaylist)
	tell application "iTunes"
		set myPlaylist to playlist selectedPlaylist
		set all_tracks to the number of myPlaylist's tracks
		set temp1 to {}
		set To_Go to {}
		
		repeat with i from 1 to all_tracks
			set this_dbid to the database ID of track i of myPlaylist
			
			if this_dbid is in temp1 then -- if this database id is already in our collection...
				copy i to end of To_Go -- then this track is a dupe; copy its index to our To_Go list
			else -- if not, it's first time we've seen track, so...
				copy this_dbid to end of temp1 --put it in our collection
			end if
		end repeat
		-- To_Go now contains indices of tracks which are dupes 
		
		-- total number of tracks to nix for dialog
		set to_nix to To_Go's length
		
		--If you must delete, do it backwards, ie: 
		
		repeat with x from to_nix to 1 by -1
			copy (item x of To_Go) to j
			delete file track j of myPlaylist
		end repeat
		
		set singplur to " entries were "
		if to_nix = 1 then set singplur to " entry was "
	end tell
end removeDuplicateTracksFromPlaylist

on showChoiceDialog()
	set question to display dialog "Would you like to create a file with Spotify links of your songs, place the songs in iTunes playlists (one match, multiple matches, no match) after searching in Spotify or both?" buttons {buttonSpotify, buttonPlaylists, buttonBoth} default button 3
	set answer to button returned of question
	return answer
end showChoiceDialog