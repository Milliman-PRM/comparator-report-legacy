/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Add passaround . 

### DEVELOPER NOTES:
	*/


options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/* Libnames */

libname M020_Out "&M020_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

proc sql;
	create table M020_out.passarounds as
	select
		cats(compress(put(cur_clm_uniq_id,Z13.)),"PTA") as claim_id,
		prvdr_oscar_num as CCN,
		atndg_prvdr_npi_num as attending_prv_npi,
		oprtg_prvdr_npi_num as operating_prv_npi
	from M020_Out.cclf1_parta_header
	;
quit;



%put System Return Code = &syscc.;
