/*
### CODE OWNERS: Matthew Hawthorne, Jason Altieri

### OBJECTIVE:
	Call the MSSP import functions. 

### DEVELOPER NOTES:
	*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "%sysget(PRMCLIENT_LIBRARY_HOME)sas\mssp\import_mssp_assignment_wrap.sas" / source2;

/*Run the assignment functions*/
%import_mssp_assignment_wrap()

%put System Return Code = &syscc.;

