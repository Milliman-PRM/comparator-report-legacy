/*
### CODE OWNERS: Anna Chen, Jack Leemhuis, Jason Altieri, Sarah Prusinski
### OBJECTIVE:
	Create a Supp program that can transfer the client market split reference file from txt file to csv. This program is for BSG only. 

	The relevant table in the excel file needs to be converted into a two column CSV with HICNO and Market.


### DEVELOPER NOTES:
	

*/

options sasautos = ("S:\Misc\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;

/*Libnames*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Import the client market split reference file.*/
data Market_Splits_import (drop = MARKET_NAME_Orig where = (upcase(market_name) ne "MA"));
  	infile "&Path_Project_Received_Ref.\Market_Split_Staged.csv" 
	delimiter=','
	lrecl = 1000 truncover dsd firstobs = 2;
 	input 
		  HICNO :$11.
 	      MARKET_NAME_Orig :$48.
		  ;
	format market_name $48.;

	market_name = scan(propcase(MARKET_NAME_Orig),1," ");
run;

/*Transpose the data to the desired format.*/
proc sort data = Market_Splits_import out = Market_Splits_import_sorted;
	by market_name;
run;

data Market_Splits_group;
	set Market_Splits_import_sorted;
	by market_name;
		if first.market_name then count = 0;
		   count+1;
run;

proc sort data = Market_Splits_group out = Market_Splits_group_sorted;
	by count;
run;

proc transpose data = Market_Splits_group_sorted 
	out = Market_Splits_trans (drop = count _name_);
		by count;
		id market_name;
		var HICNO;
run;

/*Output the new table into csv format.*/
proc export data = Market_Splits_trans
	outfile= "&Path_Project_Received_Ref.\Market_Splits.csv"
	dbms=csv replace;
run;

%put System Return Code = &syscc.;
