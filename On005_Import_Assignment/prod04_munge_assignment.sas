/*
### CODE OWNERS: Shea Parkes

### OBJECTIVE:
	Get assignment information ready for client datamart.

### DEVELOPER NOTES:
	Need something just plausible enough.
		Assignment status credibility should be high.
		Assigned physician name should just have a plausible entry.
		Physician network status will just be sloppy at this time.
*/
options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

libname M015_Out "&M015_Out." access=readonly;
libname M017_Out "&M017_Out.";
libname M020_Out "&M020_Out." access=readonly; /*This is accessed out of "order"*/


/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/




/*
	TODO: Determine assigned NPI (not just TIN)

	From assignment: most common npi per tin
	From claims: most common npi per tin by claim count (PCP specialty claims only from cclf5_partb_phys only)
	Map NPIs onto TINs
	Fall back on TIN if have to and just make an entry in 
*/

/*
	TODO: Fill in non-assigned members.

	Fill in rest of members from CCLF8 with assignement_indicator = N
*/

/*
	TODO: Make timeline assignment.

	Break yearly assignment into quarters.  Last quarter is priority 3, rest are priority 1.
	Quarterly assignment gets priority 2.
	Then brake overlaps by priority.
	Extend oldest back to date_crediblestart.

	Extend the newest forwards to 2099
	Add a blanket underlying period of non-assigned for all members.
*/

/*
	TODO:

	Assume all the assigned NPIs are in-network (including the ones we inferred from TIN links in claims)
	Scrape the prv_names from NPI file just because it is required on client_physician
*/


%put System Return Code = &syscc.;
