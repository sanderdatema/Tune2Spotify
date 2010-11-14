------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
-- Search Spotify in iTunes
--
-- By Sander Datema (sanderdatema@gmail.com)
--
-- Purpose: mark songs in an iTunes playlist with spotify_true, spotify_false or spotify_multiple
-- These tags will be added to the end of the notes field of each song.
-- Note that double spaces will be removed from your notes!
--
--
-- If you like this script, please consider buying me a beer or coffee: http://j.mp/c8veE2
-- Thanks!
--
-- Please edit the options below to your needs.
------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------
-- Note: this script depends on XML Tools by Late Night Software: http://j.mp/d9JvNR
------------------------------------------------------------------------------------------------------------------

-- If you don't want a file with a list of all the found Spotify links, set this to false
property makeSpotifyLinkList : true

-- If you don't want the spotify_tags to be added to your songs, set this to false
property addSpotifyTagsToiTunes : true

-- Fuzzy search, set false to not include the album in the search
property useAlbumInSearch : true

-- Set to true if you want to reprocess songs that already have a spotify_tag
property reprocessTagged : false

-- Set this to true if you want the script to remove all the spotify_tags from the selected playlist
-- The script will not search Spotify if you set this to true
-- Note: all spotify_tags will be removed from the selected playlist!
property removeAllTags : true


------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
-- Nothing to edit after this line.
------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
global songsProcessed
global tagTrueCount
global tagFalseCount
global tagMultipleCount
global spotifyLinksCount
global removedTagsCount
global songsSkipped
global spotifyLinkList
global countryToCheck

property theTagList : {"spotify_false", "spotify_multiple", "spotify_true"}
property spotifySearchUrl : "http://ws.spotify.com/search/1/track?q="

-- DEBUG
property debugging : true

my main()
on main()
	logEvent("====================================================================")
	logEvent("============= Start of Debug Session ===============================")
	logEvent("====================================================================")
	
	
	-- First a few checks. If it fails, the script will end.
	logEvent("Start checkups.")
	my startupCheck()
	logEvent("Checkup ok.")
	
	-- Now lookup every song in the playlist on Spotify or remove all the tags
	my processSelectedSongs(getSelection())
	
	-- Done! :)
	displayEndMessage()
	
	-- If you like it, please donate!
	showDonateDialog()
	
	-- End of debugging
	logEvent("====================================================================")
	logEvent("=============== End of Debug Session ===============================")
	logEvent("====================================================================")
end main

------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------
-- Methods
------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------

-- If this check fails, the script will end.
on startupCheck()
	-- If addSpotifyTagsToiTunes, makeSpotifyLinkList and removeAllTags are all false, there's nothing to do!
	if (addSpotifyTagsToiTunes is false and makeSpotifyLinkList is false and removeAllTags is false) then
		display dialog "There is nothing for me to do! You set all options to false." buttons {"Oops"} default button 1
		exitScript()
	end if
	
	-- Reset all counters
	set songsProcessed to 0
	set tagTrueCount to 0
	set tagFalseCount to 0
	set tagMultipleCount to 0
	set spotifyLinksCount to 0
	set songsSkipped to 0
	set removedTagsCount to 0
	
	-- Find which country we are in
	set countryToCheck to getCountryFromIP()
end startupCheck

-- Decide what to do with the selected songs
on processSelectedSongs(trackList)
	if removeAllTags is true then
		my removeAllTagsFromSelection(trackList)
	else
		my lookupSongs(trackList)
	end if
end processSelectedSongs

-- Lookup songs in Spotify from given selection of songs
on lookupSongs(trackList)
	tell application "iTunes"
		-- Preserve indexing (in case of smart playlists that change)
		set originalIndex to fixed indexing
		set fixed indexing to true
		
		-- To add the Spotify links to a file, make the new file first
		if makeSpotifyLinkList is true then my createSpotifyLinkListFile()
		
		-- Go through every single song
		repeat with thisTrack in trackList
			my logEvent("--------------------")
			
			-- Constructing search query
			-- If fuzzy search is selected we need to remove some data in the search query
			set songAlbum to thisTrack's album
			if useAlbumInSearch is false then set songAlbum to ""
			set query to thisTrack's name & " " & songArtist & " " & songAlbum
			
			my logEvent("Processing song \"" & thisTrack's name & "\" by \"" & thisTrack's artist & "\" on \"" & thisTrack's album & "\"")
			
			-- Check for spotify_tags already in the song
			set hasTags to my checkForTags(thisTrack's comment)
			
			if hasTags is true and reprocessTagged is false and makeSpotifyLinkList is false then
				my logEvent("Song already tagged, skipping")
				set songsSkipped to songsSkipped + 1
			else -- Search the song in Spotify
				set searchResult to my searchSong(query)
				if searchResult is not false then -- if false, then an error occured.
					set thisTrack's comment to my addSpotifyTagsToTrack(searchResult, thisTrack's comment)
					my addSpotifyLinksToFile(searchResult)
				else
					-- Just skip this song
					my logEvent("\"" & thisTrack's name & "\" was skipped. Error?")
					set songsSkipped to songsSkipped + 1
				end if
			end if
			
			set songsProcessed to songsProcessed + 1
			my logEvent("--------------------")
		end repeat
		
		-- Put indexing back to what it was
		set fixed indexing to originalIndex
	end tell
end lookupSongs

-- Add the Spotify links to a file if configured to do so
on addSpotifyLinksToFile(songData)
	if makeSpotifyLinkList is false or (count of songData) is 0 then return
	
	set songSpotifyLink to item 1 of songData
	my logEvent("Adding Spotify link \"" & songSpotifyLink & "\" to file")
	tell application "TextEdit"
		make new paragraph at end of text of spotifyLinkList with data songSpotifyLink & return
	end tell
	set spotifyLinksCount to spotifyLinksCount + 1
end addSpotifyLinksToFile

-- Add the spotify_tag to the track if configured to do so
on addSpotifyTagsToTrack(songData, targetComment)
	if addSpotifyTagsToiTunes is false then return
	
	if (count of songData) is 1 then -- One match found in Spotify
		my logEvent("Processing single match")
		return addTag("spotify_true", targetComment)
		set tagTrueCount to tagTrueCount + 1
	else if (count of songData) > 1 then -- Two or more matches found in Spotify
		my logEvent("Processing multiple matches")
		return addTag("spotify_multiple", targetComment)
		set tagMultipleCount to tagMultipleCount + 1
	else if (count of songData) is 0 then -- No match found
		my logEvent("Processing no match")
		set tagFalseCount to tagFalseCount + 1
		return addTag("spotify_false", targetComment)
	end if
end addSpotifyTagsToTrack

-- Remove all spotify_tags from selected tracks
on removeAllTagsFromSelection(trackList)
	tell application "iTunes"
		-- Preserve indexing (in case of smart playlists that change)
		set oldfi to fixed indexing
		set fixed indexing to true
		
		-- Go through every single song
		repeat with thisTrack in trackList
			set songComment to my splitText(" ", thisTrack's comment)
			
			set songComment to my removeItemsFromList(theTagList, songComment) -- Remove spotify_tags if present.
			
			set thisTrack's comment to my joinList(" ", songComment)
			set songsProcessed to songsProcessed + 1
			set removedTagsCount to removedTagsCount + 1
		end repeat
		-- Put indexing back to what it was
		set fixed indexing to oldfi
	end tell
end removeAllTagsFromSelection

-- Search Spotify for the given words
on searchSong(searchQuery)
	set searchQuery to my splitText(" ", searchQuery) -- Convert string to list
	-- And put it all back together again
	set searchQuery to my joinList("+", searchQuery) -- Use + as the delimiter
	-- Remove illegal characters that curl doesn't like
	set searchQuery to my stripIllegalCharacters({"[", "]", "'", "&", "{", "}", "!", "@", "$", "#", "%", "?", "/", "\"", "++"}, searchQuery)
	
	set searchUrl to spotifySearchUrl & searchQuery
	my logEvent("Search url is \"" & searchUrl & "\"")
	
	-- Use curl to fetch the xml results from Spotify's metadata API
	-- Only 10 requests per second are allowed, so we delay at least a 10th of a second
	delay 0.1
	set xmlResult to do shell script "curl " & quoted form of searchUrl
	
	if xmlResult is "" then -- No XML was returned!
		logEvent("xmlResult was empty, returning")
		return false
	end if
	
	-- Use the XML Tools by Late Night Software
	set xmlResult to parse XML xmlResult
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
		my logEvent("One match, returning result")
		return searchResult
	else if resultCount > 1 then -- Multiple matches found
		set searchResult to {}
		set trackList to my getElements(xmlResult, "track")
		
		my logEvent("Multiple results, extracting tracks now")
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
		
		my logEvent("Most popular track link: \"" & item 1 of newSearchResult & "\"")
		my logEvent("Returning result of multiple tracks")
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

-- Convert givenlist to a string
on joinList(delimiter, someList)
	set prevTIDs to AppleScript's text item delimiters
	set AppleScript's text item delimiters to delimiter
	set output to "" & someList
	set AppleScript's text item delimiters to prevTIDs
	return output
end joinList

on getAnElement(theXML, theElementName)
	-- find and return a particular element (this presumes there is only one instance of the element)
	
	repeat with anElement in XML contents of theXML
		if class of anElement is XML element and XML tag of anElement is theElementName then
			return contents of anElement
		end if
	end repeat
	
	return missing value
end getAnElement

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

on getSpotifyLink(trackXML)
	try
		return href of XML attributes of trackXML
	on error number -1728
		return ""
	end try
end getSpotifyLink

on getElements(theXML, theElementName)
	-- find and return all instatnces of a particular element
	
	local theResult
	
	set theResult to {}
	repeat with anElement in XML contents of theXML
		if class of anElement is XML element and ¬
			XML tag of anElement is theElementName then
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
on stripIllegalCharacters(theCharacters, theString)
	repeat with theCharacter in theCharacters
		set theString to my replaceText(theCharacter, "", theString)
	end repeat
	
	return theString
end stripIllegalCharacters

-- Exit the script as if the user cancelled it
on exitScript()
	error number -128
end exitScript

-- Add a spotify_tag to the song's comment
on addTag(theTag, theString)
	set theList to my splitText(" ", theString)
	
	set theCurrentTagList to removeItemsFromList(theTag, theTagList) -- Remove the needed tag from the unwanted list	
	set theList to my removeItemsFromList(theCurrentTagList, theList) -- Remove spotify_tags if present.
	
	if theList does not contain theTag then -- No need to add it twice
		logEvent("Tag " & theTag & " was not in the list, so adding now")
		set end of theList to theTag -- Add the tag
	else
		logEvent("Tag " & theTag & " was already in the list, not adding again")
	end if
	return joinList(" ", theList)
end addTag

-- Check for existence of the spotify_tags in the given string
on checkForTags(theString)
	set theList to my splitText(" ", theString)
	repeat with theTag in theTagList
		if theList contains theTag then
			return true
		end if
	end repeat
	return false
end checkForTags

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

-- Round up and show stats of current operation
on displayEndMessage()
	set lineBreak to return
	
	set songWord to pluralize("song", songsProcessed)
	set line1 to "Total " & songWord & " processed: " & songsProcessed
	logEvent(line1)
	
	set songWord to pluralize("song", songsSkipped)
	set line1a to songsSkipped & " " & songWord & " skipped."
	logEvent(line1a)
	
	set songWord to pluralize("song", tagFalseCount)
	set line2 to tagFalseCount & " " & songWord & " could not be found."
	logEvent(line2)
	
	set songWord to pluralize("song", tagTrueCount)
	set line3 to tagTrueCount & " " & songWord & " had one match."
	logEvent(line3)
	
	set songWord to pluralize("song", tagMultipleCount)
	set line4 to tagMultipleCount & " " & songWord & " had multiple matches."
	logEvent(line4)
	
	set songWord to pluralize("song", spotifyLinksCount)
	set linkWord to pluralize("link", spotifyLinksCount)
	set line5 to spotifyLinksCount & " Spotify " & linkWord & " put in a textfile."
	logEvent(line5)
	
	set songWord to pluralize("song", removedTagsCount)
	set line6 to removedTagsCount & " " & songWord & " stripped of spotify_tags."
	logEvent(line6)
	
	tell application "iTunes"
		if removeAllTags is true then
			display dialog line1 & lineBreak & lineBreak & line6 buttons {"Ok, thanks!"} default button 1
		else
			display dialog line1 & lineBreak & line1a & lineBreak & line2 & lineBreak & line3 & lineBreak & line4 & lineBreak & line5 & lineBreak & line6 buttons {"Ok, thanks!"} default button 1
		end if
	end tell
end displayEndMessage

-- Pluralize the given word (simple version)
on pluralize(itemWord, itemCount)
	if itemCount > 1 or itemCount = 0 then
		return itemWord & "s"
	else
		return itemWord
	end if
end pluralize

-- Show the dialog asking people to donate
on showDonateDialog()
	tell application "iTunes"
		set question to display dialog "If you like this Spot-in-iTunes script, please consider buying me a beer or a coffee. I'd appreciate that!" buttons {"Yeah, why not?", "I don't like this script", "I already donated"} default button 1
		set answer to button returned of question
	end tell
	if answer is equal to "Yeah, why not?" then
		open location "http://j.mp/c8veE2"
	end if
end showDonateDialog

-- Write a line of text to a log file
-- From leenoble_uk (http://j.mp/b1CmVH)
on logEvent(themessage)
	if debugging is false then return
	set themessage to my stripIllegalCharacters({"[", "]", "'", "{", "}", "!", "@", "$", "#", "%", "?", "(", ")"}, themessage)
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

on createSpotifyLinkListFile()
	tell application "TextEdit"
		my logEvent("Creating new Spotify playlist document")
		set spotifyLinkList to make new document
	end tell
end createSpotifyLinkListFile

-- From Kevin Bradley (http://j.mp/assMpB)
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
