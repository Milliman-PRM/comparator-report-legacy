"""
## CLIENT CODE/NAME: 0273NYP / New York Premier

## CODE OWNERS: Steve Gredell
### OWNERS ATTEST TO THE FOLLOWING:
  * The `master` branch will meet Milliman QRM standards at all times.
  * Deliveries will only be made from code in the `master` branch.
  * Review/Collaboration notes will be captured in Pull Requests.

### OBJECTIVE:
  New York sFTPs us files, this script will track new files as well as make a list of all files in the directory

### DEVELOPER NOTES:
  <What future developers need to know.>
"""
import sys, os, zipfile
sys.path.append(os.environ['USERPROFILE'])


root = 'S:/SecureFTP/Premier'
workingDir = "S:/PHI/0273FAL/3.NYP-0273FAL(Steves_FTP_list)/"
logName = "output.txt"
newDataName = "newDataRecieved.txt"
oldFileName = "NYP Data Received.txt"
fullFileName = "fullFileList.txt"

#==============================================================================
# LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE
#==============================================================================



with open(workingDir + logName, 'w+') as logOut:
	with open(workingDir + newDataName, 'w+') as newData:
		with open(workingDir + oldFileName, 'r') as oldData:
			with open(workingDir + fullFileName, 'w+') as allData:
				existingFiles = oldData.read()	# read the existing file list into a string to compare	
				for path,dirs,files in os.walk(root): # walk the root dir to find every file contained in it and it's subfolders
					for file in files: # loop through the list of all the files we found
						if file.endswith(".zip") or file.endswith(".ZIP"): 
							with zipfile.ZipFile(os.path.join(path,file), 'r') as myzip:
								logOut.write("Contents of zip file are: " + str(myzip.namelist()))
								for fName in myzip.namelist(): # loop through each zip file to get the filenames within
									modName = fName.split('/')
									modName = modName[len(modName) - 1] #select the last item in the list, which should be our file name
									if modName != "":
										files.append(modName)
							myzip.close()
						elif existingFiles.find(file) < 0:
							logOut.write("find result was: " + str(existingFiles.find(file)) + '\n')
							logOut.write("found new file " + file + '\n')
							newData.write(file + "\n")
						if file.endswith(".zip") == False and file.endswith(".ZIP") == False:
							allData.write(file + "\n")						
			allData.close()
		oldData.close()
	newData.close()
logOut.close()