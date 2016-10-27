/*
### CODE OWNERS: Jason Altieri, David Pierce

### OBJECTIVE:
  Hack the 073_outclaims_prm to deal with incorrect dollars/sign of days

### DEVELOPER NOTES:
	
*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/* Libnames */
libname M030_Out "&M030_Out.";

data M030_Out.inpclaims;
set M030_Out.inpclaims;
If FromDate ge mdy(10,1,2015) and ICDVersion = '09' then ICDVersion = '10';
run; 

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%put System Return Code = &syscc.;
