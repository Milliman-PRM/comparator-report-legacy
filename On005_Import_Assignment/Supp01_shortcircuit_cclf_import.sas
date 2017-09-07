/*
### CODE OWNERS: Matthew Hawthorne
### OBJECTIVE:
	 Shortcircuit the CCLF Import program
### DEVELOPER NOTES:
	*/

%include "%sysget(INDYHEALTH_LIBRARY_HOME)\include_sas_macros.sas" / source2;
options compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "%sysget(PRMCLIENT_LIBRARY_HOME)sas\mssp\shortcircuit-cclf-import.sas" / source2;

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Run the 020 import programs*/
%shortcircuit_cclf_import()

%put System Return Code = &syscc.;
