/*
### CODE OWNERS: Jack Leemhuis, Jason Altieri

### OBJECTIVE:
	Re-create the HCG grouper output outclaims data set from prm custom claims data set (outclaims_prm)
    by splitting off non HCG grouper outputs.

### DEVELOPER NOTES:
	1) Currently, this program is only for the following five ACOs: BSG, FHS, HPH, PVA, and WMH
	2) Only using data paid through September 2015 (201509), which is the last NYP quarterly deliverable

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Create macro that outputs HCG grouper outclaims*/

%macro outclaims(aco);

/*Libnames*/
libname M040_Out "&M040_Out.";
libname M073_Out "&M073_Out." access=readonly;

%GetVariableInfo(m073_out.outclaims_prm,varinfo)

proc sql noprint;
	select varname
	into: var_keep separated by ' '
	from varinfo
	where upcase(substr(varname,1,4)) ne "PRM_"
	;
quit;

%put &=var_keep.;

data M040_Out.outclaims;
	set M073_Out.outclaims_prm;
	keep &var_keep.;
run;

libname M040_Out clear;
libname M073_Out clear;

%mend;

/*BSG 201509*/
/*S:\PHI\0273NYP\3.005-0273NYP(07-BSG)\5-Support_Files\Data_Thru_201509_M5\driver.bat*/
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%outclaims(bsg);

/*FHS 201509*/
/*S:\PHI\0273NYP\3.009-0273NYP(11-FHS)\5-Support_Files\Data_Thru_201509_M5\driver.bat*/
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%outclaims(fhs);

/*HPH 201509*/
/*S:\PHI\0273NYP\3.011-0273NYP(13-HPH)\5-Support_Files\Data_Thru_201509_M5\driver.bat*/
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%outclaims(hph);

/*PVA 201509*/
/*S:\PHI\0273NYP\3.003-0273NYP(05-PVA)\5-Support_Files\Data_Thru_201509_M5_Warm\driver.bat*/
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%outclaims(pva);

/*WMH 201509*/
/*S:\PHI\0273NYP\3.027-0273NYP(29-WMH)\5-Support_Files\Data_Thru_201509_M5\driver.bat*/
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%outclaims(wmh);


%put System Return Code = &syscc.;

