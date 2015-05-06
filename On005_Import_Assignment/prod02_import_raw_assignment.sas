/*
### CODE OWNERS: Shea Parkes, Kyle Baird

### OBJECTIVE:
	Bring raw assignment information into SAS.

### DEVELOPER NOTES:
	This could likely be replaced with a codegen step in Python.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

libname M017_Out "&M017_Out.";
/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




data M017_Out.timeline_assign_extract;
	infile
		"&M017_Out.timeline_assign_extract.txt"
		dsd
		delimiter = "~"
		firstobs = 2
		truncover
		lrecl = 32767
		;
	input
		date_start :YYMMDD10.
		date_end :YYMMDD10.
		hicno :$11.
		tin :$10.
		npi :$10.
		;
	format date_: YYMMDDd10.;
run;
%LabelDataSet(M017_Out.timeline_assign_extract)

%put System Return Code = &syscc.;
