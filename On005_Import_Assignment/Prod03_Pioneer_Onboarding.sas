/*
### CODE OWNERS: Kyle Baird, David Pierce, Jason Altieri

### OBJECTIVE:
	Create client reference files for Pioneer ACOs

### DEVELOPER NOTES:
	Pioneer ACOs do not receive quarterly assignment files.  As such, we will
	attempt to assign providers to members using claims data.  At this point,
	our current needs to do not require exact assignment information.  Full CMS
	assignment logic was not implemented at this time.
*/
%include "%sysget(INDYHEALTH_LIBRARY_HOME)\include_sas_macros.sas" / source2;
%include "%sysget(MEDICARE_ACO_ONBOARDING_HOME)\Supp01_shared.sas" / source2;
%include "%sysget(PRMCLIENT_LIBRARY_HOME)sas\mssp\shortcircuit-cclf-import.sas" / source2;
%include "&M008_cde.func06_build_metadata_table.sas";
%Include "&M008_Cde.Func02_massage_windows.sas" / source2;

%AssertThat(
	%upcase(&cclf_ccr_absent_any_prior_cclf8.)
	,eq
	,EXCLUDE
	,ReturnMessage=Only applicable for Pioneer ACOs.
	,FailAction=endactivesassession
	)

/* Libnames */
libname ref_prod "&path_product_ref." access=readonly;
libname M015_Out "&M015_Out." access=readonly;
libname M017_Out "&M017_Out." access=readonly;
libname M020_Out "&M020_Out." access=readonly;
libname
	%sysfunc(ifc("%upcase(&project_id_prior.)" eq "NEW"
		,M035_out "&M035_out." /*If it is a warm start stacked member rosters will be seeded here*/
		,M035_old "&M035_old." /*Otherwise, grab from prior project*/
		))
	access=readonly
	;
libname M018_Out "&M018_Out.";

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Run the 020 import programs*/
%shortcircuit_cclf_import()

/*Import client reference information from claims file.*/
%include "%GetParentFolder(0)Supp02_import_pioneer_info_wrap.sas" / source2;

%put System Return Code = &syscc.;
