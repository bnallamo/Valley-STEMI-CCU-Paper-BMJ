*Stata Version 14.2*
*August 20, 2019*

/* Purpose: To evaluate the association between ICU admission and 30-day mortality
	among STEMI patients with discretionary ICU needs. We will use an instrumental 
	variable analysis with the differential distance to a high ICU use hospital 
	for STEMI as the instrument.

Datasets used:
	2014 and 2015 MedPAR for patient-level data
	2014 and 2015 American Hospital Association surveys for hospital-level data
	2010 census for patient-level geographic coordinates, county codes, median income by ZIP code
	National Center for Health Statistics for urban-rural status

Table of Contents
	1. Data formatting using 2014 and 2015 MedPAR
		a. Identify STEMI and ICU patients
		b. Drop patients based on exclusion criteria
		c. Create outcome variable and covariates
	2. Creating the instrument
		a. Hospital-level ICU admission rates
		b. Differential distance variable
	3. Adding hospital-level covariates
	4. Analysis
		a. Wooldridge's score test of endogeneity
		b. Patient characteristics by median differential distance (Table 1)
		c. Patient characteristics by ICU admission (Table 2)
		d. Hospital characteristics by ICU use (Table 3)
		e. Main results (Table 4)
		f. Caterpillar plot (Figure 1)
		g. Subgroup analyses (Figure 2)
		h. Two-stage residual inclusion model
		i. Estimating probability of ICU admission with increasing differential distance
		j. Estimating proportions of marginal subgroups
		k. Characterizing marginal subgroups
		l. Estimating ICU admission and 30-day mortality by age */

cd "C:\Users\valleyt\Desktop\Research\IV STEMI\stemi"
log using stemi_data022819.smcl

*****************************************************
**  1. Data Formatting using 2014 and 2015 MedPAR  **
*****************************************************

*** Identify STEMI patients***

/* 2014 and 2015 MedPAR files include all patient-level discharges. Each year 
	is too large and is split into two files. Diagnosis codes are in wide form.
	A primary diagnosis code for STEMI is identified below. */

use "C:\Users\valleyt\Desktop\2014_1", clear

gen stemi = 0
foreach var of varlist dx1 {
foreach num of numlist 0/9 {
replace stemi = 1 if `var' == "4100`num'"
replace stemi = 1 if `var' == "4101`num'"
replace stemi = 1 if `var' == "4102`num'"
replace stemi = 1 if `var' == "4103`num'"
replace stemi = 1 if `var' == "4104`num'"
replace stemi = 1 if `var' == "4105`num'"
replace stemi = 1 if `var' == "4106`num'"
replace stemi = 1 if `var' == "4108`num'"
replace stemi = 1 if `var' == "4109`num'"
}
}
keep if stemi == 1
save stemi_2014_1, replace

use "C:\Users\valleyt\Desktop\2014_2", clear

gen stemi = 0
foreach var of varlist dx1 {
foreach num of numlist 0/9 {
replace stemi = 1 if `var' == "4100`num'"
replace stemi = 1 if `var' == "4101`num'"
replace stemi = 1 if `var' == "4102`num'"
replace stemi = 1 if `var' == "4103`num'"
replace stemi = 1 if `var' == "4104`num'"
replace stemi = 1 if `var' == "4105`num'"
replace stemi = 1 if `var' == "4106`num'"
replace stemi = 1 if `var' == "4108`num'"
replace stemi = 1 if `var' == "4109`num'"
}
}
keep if stemi == 1
save stemi_2014_2, replace

use "C:\Users\valleyt\Desktop\2015_1", clear

gen stemi = 0
foreach var of varlist dx1 {
foreach num of numlist 0/9 {
replace stemi = 1 if `var' == "4100`num'"
replace stemi = 1 if `var' == "4101`num'"
replace stemi = 1 if `var' == "4102`num'"
replace stemi = 1 if `var' == "4103`num'"
replace stemi = 1 if `var' == "4104`num'"
replace stemi = 1 if `var' == "4105`num'"
replace stemi = 1 if `var' == "4106`num'"
replace stemi = 1 if `var' == "4108`num'"
replace stemi = 1 if `var' == "4109`num'"
}
}
keep if stemi == 1
save stemi_2015_1, replace

use "C:\Users\valleyt\Desktop\2015_2", clear

gen stemi = 0
foreach var of varlist dx1 {
foreach num of numlist 0/9 {
replace stemi = 1 if `var' == "4100`num'"
replace stemi = 1 if `var' == "4101`num'"
replace stemi = 1 if `var' == "4102`num'"
replace stemi = 1 if `var' == "4103`num'"
replace stemi = 1 if `var' == "4104`num'"
replace stemi = 1 if `var' == "4105`num'"
replace stemi = 1 if `var' == "4106`num'"
replace stemi = 1 if `var' == "4108`num'"
replace stemi = 1 if `var' == "4109`num'"
}
}
keep if stemi == 1
save stemi_2015_2, replace

append using stemi_2015_1.dta, force
append using stemi_2014_1.dta, force
append using stemi_2014_2.dta, force

save stemi, replace

*Identify ICU patients*

*Identify General Ward Patients*
gen floor = 0
replace floor = 1 if (icuindcd == . & crnry_cd == .)

*Identify Intermediate Care Patients*
gen intermediate = 0
replace intermediate = 1 if ((icuindcd == 6 & (crnry_cd == . | (crnry_cd == 4)) | ///
 crnry_cd == 4 & (icuindcd == . | icuindcd == 6)))

*Identify ICU Patients*
gen icu = 0 
replace icu = 1 if floor == 0 & intermediate == 0
fre floor
fre intermediate
fre icu

***Drop patients based on exclusion criteria***

/* We excluded transfers into a hospital, psychiatric ICU admissions, patients 
	without ZIP codes or living in a U.S. territory, or admitted to a hospital 
	without ICU capabilities. */

*Drop OSH Transfers*

/* Index admissions are identified as the first admission of a patient for STEMI. */

sort bene_id dischdte
bysort bene_id: gen admit_number = _n

gen index_admission = 0
replace index_admission = 1 if admit_number == 1

unique bene_id
save, replace

/* The range of hospitalizations for a patient is 1-21. We will calculate gaps 
	in time between hospitalizations. If gap==0, then admission is treated as 
	an outside hospital transfer in. */

keep bene_id admdte dischdte hospid index_admission admit_number
reshape wide admdte dischdte hospid index_admission, i(bene_id) j(admit_number)
save stemi_temp, replace

local j = 1
local k = 2
foreach num of numlist 2/21 {
gen gap`num' = admdte`k' - dischdte`j'
local j = `j'+1
local k = `k'+1
}
destring hospid*, replace force

local j = 1
local k = 2
foreach num of numlist 2/21 {
gen oshtransfer`num' = 1 if hospid`k' != hospid`j' & gap`num' == 0
local j = `j'+1
local k = `k'+1
}
save, replace

reshape long oshtransfer, i(bene_id) j(admit_number)
collapse (max) oshtransfer, by(bene_id)
save stemi_temp, replace

use stemi, clear

merge m:1 bene_id using stemi_temp, keepusing(oshtransfer) gen(_merge1)
drop if _merge1 == 2
drop _merge1
drop if oshtransfer == 1
unique bene_id

*Drop Psychiatric ICU *

destring icuindcd, replace
destring crnry_cd, replace
drop if icuindcd == 4
unique bene_id

*Drop if no ZIP code or in U.S. territory*

destring benezip, replace
drop if benezip == .
drop if [benezip <= 999 | ///
 [benezip >= 9000 & benezip <= 9999] | [benezip >= 96200 & benezip <= 96999] | ///
 [benezip >= 96700 & benezip <= 96999] | [benezip >= 99500 & benezip <= 99999]]
unique bene_id

*Remove Hospitals without ICU Capabilities*
destring hospid, replace force
drop if hospid == .
sort hospid
unique bene_id

/* Merge 2014 and 2015 AHA surveys to add hospital-level data. Geographic 
	coordinates will be used to calculate distances between hospitals and 
	ZIP code centroids of patient residences. */

merge m:1 hospid using "C:\Users\valleyt\Desktop\Research\hospital files\rAHA2014.dta", ///
 keepusing(reg reg4 ahazip ahalat ahalong cbsa mapp5 msicbd cicbd brnbd othicbd ///
 hospbd hospbd icuperc teaching medicaid nurserat nurserat4) update replace ///
 generate(_merge4)
drop if _merge2 == 2
drop _merge2

merge m:1 hospid using "C:\Users\valleyt\Desktop\Research\hospital files\rAHA2015.dta", ///
 keepusing(reg reg4 ahazip ahalat ahalong cbsa mapp5 msicbd cicbd brnbd othicbd ///
 hospbd hospbd icuperc teaching medicaid nurserat nurserat4) update replace ///
 generate(_merge3)
drop if _merge3 == 2
drop _merge2

gen toticu = msicbd + cicbd + othicbd + brnbd
gen aha_icu = 0
replace aha_icu = 1 if toticu > 1 & toticu != .
fre aha_icu

/* Hospitals with less than 5 ICU admissions for STEMI in MedPAR, with 0 ICU beds in 
	2014 or 2015 AHA data, or with missing hospital geographic coordinates were excluded. */

bysort hospid: egen icuadmits = sum(icu) 
sum icuadmits, de
count if icuadmits < 5
drop if aha_icu == 0 | icuadmits < 5
unique bene_id

drop if ahazip == . 
unique bene_id
tab reg, m
replace reg = . if reg == 0
drop if reg == .
unique bene_id

gen hospzip = ahazip

merge m:1 hospzip using "C:\Users\valleyt\Desktop\Research\Hard copies\census bureau\temp_hosp.dta", keepusing(hosplat hosplong) update gen(_merge)
drop if _merge == 2
drop _merge

save, replace

***Create exposure variable, outcome variable, and covariates***

*Merge ZIP Code Centroids*

/* ZIP code centroids merged from 2010 census data. The geographic coordinates for 
	the ZIP code centroids of patient residences will be used with hospital 
	geographic coordinates to calculate differential distances. */

rename benezip zipcode
destring zipcode, replace

merge m:1 zipcode using "C:\Users\valleyt\Desktop\Research\Hard copies\census bureau\zip code centroids.dta", ///
keepusing(lat longit) generate(_merge)
drop if _merge == 2

rename lat benelat
rename longit benelong
rename zipcode benezip
drop _merge

destring sex, replace
destring race, replace

*By Discharge Destination*
gen discharge = .
replace discharge = 0 if dstntncd == "30"
replace discharge = 1 if (dstntncd == "01" | dstntncd == "06" | dstntncd == "08")
replace discharge = 2 if (dstntncd == "02" | dstntncd == "05" | dstntncd == "43" | ///
 dstntncd == "65" | dstntncd == "66")
replace discharge = 3 if (dstntncd == "03" | dstntncd == "04" | dstntncd == "62" | ///
 dstntncd == "63" | dstntncd == "64")
replace discharge = 4 if dstntncd == "20"
replace discharge = 5 if (dstntncd == "50" | dstntncd == "51")
replace discharge = 6 if dstntncd == "07"
label define fdischarge 0 "Still in Hospital" 1 "Home" 2 "Transferred to another Acute Care Hospital" ///
 3 "Discharged to Facility" 4 "Dead" 5 "Hospice" 6 "AMA"
label values discharge fdischarge
label variable discharge "Discharge Destination"

gen dischargeloc = 0
replace dischargeloc = 1 if discharge == 3
replace dischargeloc = 2 if discharge == 4
replace dischargeloc = 3 if discharge == 0 | discharge == 2 | discharge == 5 | ///
 discharge == 6
label define fdischargeloc 0 "Home" 1 "Facility" 2 "Dead" 3 "Other"
label values dischargeloc fdischargeloc
label variable dischargeloc "Categories of Discharge Destination"

*In-Hospital Mortality*
gen death = .
replace death = 0 if dstntncd != "20"
replace death = 1 if dstntncd == "20"

*Days Alive*
gen daysalive = death_dt - admdte
replace daysalive = 0 if daysalive < 0 & daysalive != .

*30-day Mortality*
gen death30d = .
replace death30d = 0 if daysalive > 30 | daysalive == .
replace death30d = 1 if daysalive <= 30 & daysalive != .

*By Age*
gen agecat = 0
replace agecat = 1 if age2 >= 65 & age2 < 75
replace agecat = 2 if age2 >= 75 & age2 < 85
replace agecat = 3 if age2 >= 85 & age2 != .
label define fagecat 0 "< 65" 1 "65-74" 2 "75-84" 3 "85+"
label values agecat fagecat
label variable agecat "Age by Categories"

*By Race*
gen racecat = .
replace racecat = 1 if race == 1
replace racecat = 2 if race == 2
replace racecat = 3 if race != 1 & race !=2
label define fracecat 1 "White" 2 "Black" 3 "Other"
label values racecat fracecat
label variable racecat "Race by Categories"

*National Center for Health Statistics Urban-Rural Classification*

/* NCHS Urban-Rural Classification was used. First, ZIP codes were used to 
	identify county codes. County codes were used to classify patient residences
	as urban or rural. 
	
Additional information and data accessible at: 
https://www.ncbi.nlm.nih.gov/pubmed/24776070
https://www.cdc.gov/nchs/data_access/urban_rural.htm
*/
 
merge m:1 benezip using "C:\Users\valleyt\Desktop\Research\Hard copies\census bureau\ziptocounty.dta", keepusing(county)
drop if _merge == 2
drop _merge
merge m:1 county using "C:\Users\valleyt\Desktop\Research\Hard copies\census bureau\urban-rural-fips.dta", keepusing(nchs)
drop if _merge ==2
drop _merge

unique bene_id
drop if nchs == .
unique bene_id

/* Within 2014 and 2015 MedPAR, there are 25 diagnosis codes (dx`n') and 25
	procedure codes (proc`n') available. The first diagnosis code is considered 
	the primary diagnosis. */

*By Cardiac Catheterization*
gen cath = 0
foreach var of varlist proc1-proc25 {
replace cath = 1 if `var' == "3722"
replace cath = 1 if `var' == "3723"
}

*By CABG*
gen cabg = 0
foreach var of varlist proc1-proc25 {
replace cabg = 1 if `var' == "361"
replace cabg = 1 if `var' == "3610"
replace cabg = 1 if `var' == "3611"
replace cabg = 1 if `var' == "3612"
replace cabg = 1 if `var' == "3613"
replace cabg = 1 if `var' == "3614"
replace cabg = 1 if `var' == "3615"
replace cabg = 1 if `var' == "3616"
replace cabg = 1 if `var' == "3617"
replace cabg = 1 if `var' == "3619"
}

*By Thrombolytics*
gen lytics = 0
foreach var of varlist proc1-proc25 {
replace lytics = 1 if `var' == "9910"
}

*By Palliative Care Encounter*
gen palli = 0
foreach var of varlist dx1-dx25 {
replace palli = 1 if `var' == "V667"
}

*By Invasive Mechanical Ventilation*
gen invmechvent = 0
foreach var of varlist proc1-proc25 {
replace invmechvent = 1 if `var' == "967"
replace invmechvent = 1 if `var' == "9670"
replace invmechvent = 1 if `var' == "9671"
replace invmechvent = 1 if `var' == "9672"
}
label variable invmechvent "Invasive Mechanical Ventilation"

*By Non-Invasive Mechanical Ventilation*
gen nippv = 0
foreach var of varlist proc1-proc25 {
replace nippv = 1 if `var' == "9390"
}
label variable nippv "Non-Invasive Mechanical Ventilation"

*By Mechanical Ventilation*
gen vent = 0
replace vent = 1 if invmechvent == 1 | nippv == 1

*By Respiratory Failure*
gen respfail = 0
foreach var of varlist dx1-dx25 {
replace respfail = 1 if `var' == "51881"
replace respfail = 1 if `var' == "51882"
replace respfail = 1 if `var' == "51883"
replace respfail = 1 if `var' == "51884"
replace respfail = 1 if `var' == "7991"
replace respfail = 1 if `var' == "78609"
replace respfail = 1 if `var' == "5185"
}
label variable respfail "Respiratory Failure"

*By Shock*
gen shock = 0
foreach var of varlist dx1-dx25 {
replace shock = 1 if `var' == "7855"
replace shock = 1 if `var' == "78550"
replace shock = 1 if `var' == "78551"
replace shock = 1 if `var' == "78552"
replace shock = 1 if `var' == "78553"
replace shock = 1 if `var' == "78554"
replace shock = 1 if `var' == "78555"
replace shock = 1 if `var' == "78556"
replace shock = 1 if `var' == "78557"
replace shock = 1 if `var' == "78558"
replace shock = 1 if `var' == "78559"
replace shock = 1 if `var' == "9980"
replace shock = 1 if `var' == "9584"
replace shock = 1 if `var' == "458"
}
label variable shock "Shock"

*By Hemodialysis Procedure*
gen hd = 0
foreach var of varlist proc1-proc15 {
replace hd = 1 if `var' == "3995"
}

*By Acute Kidney Injury*
gen aki = 0
foreach var of varlist dx1-dx25 {
icd9 gen akik`k' = `var', range(584*)
replace aki = 1 if akik`k' == 1
local k = `k'+1
}
drop akik*

*By Acute Kidney Injury Requiring Hemodialysis*
gen akid = 0
replace akid = 1 if aki == 1 & hd == 1

*By End Stage Renal Disease*
gen esrd = 0
gen esrdk1 = 0
gen esrdk2 = 0
foreach var of varlist dx1-dx25 {
replace esrdk1 = 1 if `var' == "5856"
}
foreach var of varlist proc1-proc15 {
replace esrdk2 = 1 if `var' == "5498"
}
replace esrd = 1 if (esrdk1 == 1 & aki == 0) | (esrdk2 == 1 & aki == 0) | (hd == 1 & aki == 0)
drop esrdk*
replace akid = 0 if aki == 0 | esrd == 1

*Intra-aortic Balloon Pump*
gen pvad = 0
foreach var of varlist proc1-proc15 {
replace pvad = 1 if `var' == "3768"
}
gen iabp = 0
foreach var of varlist proc1-proc15 {
replace iabp = 1 if `var' == "3761"
}
gen pvad_iabp = 0
replace pvad_iabp = 1 if pvad == 1 | iabp == 1

*Cardiac Arrest*
gen cardarrest = 0
foreach var of varlist dx1-dx25 {
replace cardarrest = 1 if `var' == "4271"
replace cardarrest = 1 if `var' == "4274"
replace cardarrest = 1 if `var' == "42741"
replace cardarrest = 1 if `var' == "4275"
}

*Targed Temperature Management*
gen ttm = 0
foreach var of varlist proc1-proc15 {
replace ttm = 1 if `var' == "9981"
}

*Generate Angus Organ Failure Definitions*

*Cardiovascular*
gen cvA = 0
local k=1
foreach var of varlist dx* {
icd9 gen cvorg`k' = `var' , range(785.5* 458*)
replace cvA =1 if cvorg`k'==1
local k = `k'+1
}
drop cvorg*
label variable cvA "Cardiovascular Failure"

*Respiratory*
gen respA = 0
local k=1
foreach var of varlist proc* {
icd9p gen resporg`k' = `var' , range(96.7*)
replace respA =1 if resporg`k'==1
local k = `k'+1
}
drop resporg*	
label variable respA "Respiratory Failure"
	
*Renal*
gen kidneyA = 0
local k=1
foreach var of varlist dx* {
icd9 gen renorg`k' = `var' , range (584*)
replace kidneyA = 1 if renorg`k'==1
local k = `k'+1
}
drop renorg*
label variable kidneyA "Renal Failure"

*Liver*
gen hepaticA = 0
local k=1
foreach var of varlist dx* {
icd9 gen livorg`k' = `var' , range(570* 573.4)
replace hepaticA = 1 if livorg`k'==1
local k = `k'+1
}
drop livorg*
label variable hepaticA "Liver Failure"

*Hematologic*
gen hemA = 0
local k=1
foreach var of varlist dx* {
icd9 gen hemorg`k' = `var' , range(287.4* 287.5* 286.9* 286.6*)
replace hemA = 1 if hemorg`k' == 1
local k = `k'+1
}
drop hemorg*
label variable hemA "Hematologic Failure"

*Neurologic*
gen neuroA = 0
local k=1
foreach var of varlist dx* {
icd9 gen neuroorg`k' = `var' , range(248.3* 293* 348.1*)
replace neuroA = 1 if neuroorg`k'==1
local k = `k'+1
}
drop neuroorg*
label variable neuroA "Neurologic Failure"

*Calculating the number of non-resp organ failures based upon above sepsis coding*
egen totorgfA = rowtotal(cvA respA kidneyA hepaticA hemA neuroA)
label variable totorgfA "Number of Organ Failures By Angus"

gen orgfail = 0
replace orgfail = 1 if totorgfA > 0 & totorgfA != .
label define forgfail 0 "0" 1 "1+" 
label values orgfail forgfail
label variable orgfail "Organ Failures"

*Generate Elixhauser Comorbidities*
destring drg_c, replace
save, replace

/* Additional information on the Elixhauser Comorbidity Software can be found at:
https://www.hcup-us.ahrq.gov/toolssoftware/comorbidity/comorbidity.jsp#download
*/

elixhaus stemi stemi 1 dx drg_cd

use stemi, clear

*Income by ZIP Code*

/* Median income by ZIP code is obtained from 2010 census data */

destring benezip, replace force
merge m:1 benezip using "C:\Users\valleyt\Desktop\Research\Hard copies\census bureau\2006-2010 income by zip.dta" 
drop if _merge == 2
drop _merge

*Categories of Income by ZIP Code*
gen catinc = .
replace catinc = 1 if medianinc < 40000
replace catinc = 2 if medianinc >= 40000 & medianinc < 100000
replace catinc = 3 if medianinc >= 100000
label define fcatinc 1 "Median Income < $40,000" 2 "Median Income $40,000-$100,000" ///
 3 "Median Income > $100,000"
label values catinc fcatinc
label variable catinc "Categories of Income by ZIP Code"

save, replace 

******************************************
**  Hospital-level ICU admission rates  **
******************************************

/* Hospitals in the top quartile of ICU admission rates are defined as high 
	ICU use hospitals. */

bysort hospid: egen stemiicurate = mean(icu)
bysort hospid: egen stemiintermrate = mean(intermediate)
collapse (mean) stemiicurate (mean) stemiintermrate, by(hospid)
sum stemiicurate, de
sum stemiintermrate, de

xtile stemiicurate4 = stemiicurate, nq(4)
label variable stemiicurate4 "Quartiles of ICU Use"

gen stemiicucat = .
replace stemiicucat = 0 if stemiicurate4 == 1 | stemiicurate4 == 2 | stemiicurate4 == 3
replace stemiicucat = 1 if stemiicurate4 == 4
label define fstemiicucat 0 "< 75%ile of ICU Use" 1 "> 75%ile of ICU Use"
label values stemiicucat fstemiicucat
label variable stemiicucat "Categories of ICU Use"

save stemi_hosplev_temp, replace

use stemi, clear

*Merge Rate of ICU Admission*
merge m:1 hospid using stemi_hosplev_temp, keepusing(stemiicurate stemiintermrate ///
 stemiicurate4 stemiicucat) generate(_merge)
drop if _merge == 2
drop _merge

save, replace

**************************************
**  Differential distance variable  **
**************************************

*Make Hospital-Level File*
keep hospid hosplat hosplong
duplicates drop hospid, force
save stemi_hosploc, replace

*Make Patient-Level File*
use stemi, clear
keep medpar_id benelat benelong
save stemi_ptloc, replace

/* Patient-level file contains 110,426 observations. This file becomes too large
	once crossed. This file will be brokedn into three smaller files. */ 

use stemi_ptloc, clear
keep in 1/36814
save stemi_ptloc_1, replace
use stemi_ptloc, clear
keep in 36815/73628
save stemi_ptloc_2, replace
use stemi_ptloc, clear
keep in 73629/110426
save stemi_ptloc_3, replace

*Cross Patient- and Hospital-Level Files*

forvalues i=1/3 {
use stemi_ptloc_`i', clear
cross using stemi_hosploc
save stemi_cross_`i', replace
local i=`i'+1 
}

/* These three crossed files are too large to obtain distances. Files 1 and 2 contain 
	63,577,778 observations and will be broken into 2 files. File 3 contains 
	63,550,146 observations and will be broken into 3 files. */

local j=1
forvalues k=1/2 {
use stemi_cross_`k', clear
keep in 1/31788889
save stemi_cross2_`j'
local j=`j'+1
use stemi_cross_`k', clear
keep in 31788890/63577778
save stemi_cross2_`j'
local j=`j'+1
local k=`k'+1 
}
use stemi_cross_3, clear
keep in 1/21183382
save stemi_cross2_5
use stemi_cross_3, clear
keep in 21183383/42366764
save stemi_cross2_6
use stemi_cross_3, clear
keep in 42366765/63550146
save stemi_cross2_7

/* The geodist command calculates the distance between two sets of geographic
	coordinates as the crow flies. Here, it finds the distance between a patient's
	residence to all U.S. hospitals included in the analysis. Distances > 300 
	miles are excluded to limit the size of the file, as it is unlikely that 
	any patient traveled more than 300 miles for STEMI care. */

forvalues j=1/7 {
use stemi_cross2_`j', clear
geodist benelat benelong hosplat hosplong, gen(distance) mi
label variable distance "Distance from Home to Hospital in Miles"
drop if distance > 300
save stemi_distcross_`j', replace
local j=`j'+1 
}

use stemi_distcross_1, clear
local k=2
forvalues k=2/7 {
append using stemi_distcross_`k'
local k=`k'+1 
}

*Calculate the distance to the closest hospital*
gsort medpar_id distance
bysort medpar_id: egen mindist = min(distance)

merge m:1 hospid using stemi_hosplev_temp, keepusing(stemiicucat)
drop if _merge == 2
drop _merge

*Calculate the distance to the closest high ICU use hospital*
bysort medpar_id: egen highusedist = min(distance) if stemiicucat == 1

save stemi_distcross, replace

*Collapse Back to Patient Level*

/* This dataset currently contains observations for distances from a patient's
	residence to all U.S. hospitals. We will collapse the file to include only
	the distance to the nearest hospital and to the nearest high ICU use hospital. */

collapse (mean) mindist (mean) highusedist, by(medpar_id)

save stemi_mindist, replace

use stemi, clear

*Move Distances to Main Patient File*
merge 1:1 medpar_id using stemi_mindist, keepusing(mindist highusedist)
keep if _merge == 3
drop _merge

*Calculate Differential Distance*

/* Differential distance represents the difference between the distance from 
	the patient's residence to the nearest high ICU use hospital and the 
	patient's residence to the nearest hospital of any type. */
	
gen diffdist = .
replace diffdist = highusedist-mindist
unique bene_id
drop if diffdist == . 
unique bene_id

sum diffdist, de

*ICU median distance*
gen meddist = .
replace meddist = 0 if diffdist < r(p50)
replace meddist = 1 if diffdist >= r(p50)

save, replace

****************************************
**  Adding hospital-level covariates  **
****************************************

gen admitnumber = 1
destring mapp5, replace
collapse (sum) admitnumber (sum) icu (sum) floor (sum)intermediate (sum) invmechvent ///
 (sum) nippv (sum) cath (sum) cabg (sum) lytics (mean) mapp5 (mean) reg (mean) reg4 ///
 (mean) cbsa (mean) teaching (mean) hospbd (mean) icuperc (mean) nurserat ///
 (mean) medicaid (mean) nurserat4 (mean) catinc, by(hospid)
rename admitnumber stemivol

merge 1:1 hospid using stemi_hosplev_temp, keepusing(stemiicucat stemiicurate ///
 stemiintermrate stemiicurate4) gen(_merge)
drop if _merge == 2
drop _merge

*Tertiles of Medicaid Patients Served*
xtile medicaid3 = medicaid, nq(3)
pctile pct_medicaid = medicaid, nq(3)

*Hospital Size in Total Beds*
gen hospsizecat = .
replace hospsizecat = 0 if hospbd < 100
replace hospsizecat = 1 if hospbd >= 100 & hospbd < 200
replace hospsizecat = 2 if hospbd >= 200 & hospbd != .
label define fhospsizecat 0 "< 100" 1 "100-199" 2 "200+"
label values hospsizecat fhospsizecat

*ICU Size in Proportion of Total Hospital Beds*
gen icusizecat = .
replace icusizecat = 0 if icuperc < 0.05
replace icusizecat = 1 if icuperc >= 0.05 & icuperc < 0.1
replace icusizecat = 2 if icuperc >= 0.1 & icuperc != .
label define ficusizecat 0 "< 5%" 1 "5-9.9%" 2 "10%+"
label values icusizecat ficusizecat

*Total Revascularizations at a Hospital*
gen revasc = cath+cabg+lytics
rename cath hospcath
rename cabg hospcabg
rename lytics hosplytics
rename revasc hosprevasc

*Rank Hospitals by their ICU Admission Rate for STEMI*
gen stemiicurate100 = stemiicurate*100
egen hosp_rank = rank(stemiicurate)
gen icurate = stemiicurate*100

save stemi_hosplev, replace

use stemi, clear

merge m:1 hospid using stemi_hosplev, keepusing(stemivol stemiicurate ///
 stemiicurate4 hospsizecat icusizecat hospcath hospcabg hosplytics hosprevasc)
drop if _merge==2
drop _merge

*Differential Distance in 10 Mile Increments*
gen dd10 = diffdist/10

save, replace


****************
**  Analysis  **
****************

*Wooldridge's score test of endogeneity*

/* Wooldridge's score test is similar to the Wu-Durbin-Hausman test but is reported 
	when a VCE term is used. For either test, if the test statistic is significant, then
    the variables being tested must be treated as endogenous. */

quietly ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol, first vce(cluster hospid)
estat endogenous

*Patient Characteristics by Median Differential Distance (Table 1)*

tab meddist

tab icu meddist, col 
stddiff i.icu, by(meddist)

tab intermediate meddist, col 
stddiff i.intermediate, by(meddist)

table meddist, c(mean age2 sd age2)
tab agecat meddist, col 
stddiff i.agecat, by(meddist)

tab sex meddist, col 
stddiff i.sex, by(meddist)

tab racecat meddist, col 
stddiff i.racecat, by(meddist)

tab nchs meddist, col 
stddiff i.nchs, by(meddist)

tab catinc meddist, col 
stddiff i.catinc, by(meddist)

table meddist, c(mean elixhaus sd elixhaus)
stddiff elixhaus, by(meddist)

tab respfail meddist, col 
stddiff i.respfail, by(meddist)
tab shock meddist, col 
stddiff i.shock, by(meddist)
tab cardarrest meddist, 
stddiff i.cardarrest, by(meddist)

tab cath meddist, col 
stddiff i.cath, by(meddist)
tab cabg meddist, col 
stddiff i.cabg, by(meddist)
tab lytics meddist, col 
stddiff i.lytics, by(meddist)
tab vent meddist, col 
stddiff i.vent, by(meddist)
tab akid meddist, col
stddiff i.akid, by(meddist)
tab pvad_iabp meddist, col
stddiff i.pvad_iabp, by(meddist)
tab ttm meddist, col
stddiff i.ttm, by(meddist)

tab orgfail meddist, col 
stddiff i.orgfail, by(meddist)

tab palli meddist, col 
stddiff i.palli, by(meddist)

*Patient Characteristics by ICU Admission (Table 2)*

tab icu

table icu, c(mean age2 sd age2)
tab agecat icu, col 

tab sex icu, col 

tab racecat icu, col 

tab nchs icu, col 

tab catinc icu, col 

table icu, c(mean elix_cnt sd elix_cnt)

tab respfail icu, col 
tab shock icu, col 
tab cardarrest icu, col

tab cath icu, col 
tab cabg icu, col 
tab lytics icu, col 
tab vent icu, col 
tab akid icu, col
tab pvad_iabp icu, col
tab ttm icu, col

tab orgfail icu, col 

tab palli icu, col 

bysort icu: sum los_day_cnt, de

tab dischargeloc icu, col 

*Hospital Characteristics by ICU Use (Table 3)*

use stemi_hosplev, clear

tab stemiicucat

table stemiicucat, c(mean stemiicurate sd stemiicurate)
table stemiicucat, c(mean stemiintermrate sd stemiintermrate)
table stemiicucat, c(median stemivol p25 stemivol p75 stemivol)
table stemiicucat, c(median hosprevasc p25 hosprevasc p75 hosprevasc)

tab mapp5 stemiicucat, col 
tab teaching stemiicucat, col 

tab hospsizecat stemiicucat, col 
tab icusizecat stemiicucat, col 

tab medicaid3 stemiicucat, col 

table stemiicucat, c(mean nurserat sd nurserat)

tab reg4 stemiicucat, col 

*Main Results (Table 4)*

use stemi, clear

local coV "age2 i.sex i.racecat i.nchs i.catinc totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc hospbd icuperc medicaid nurserat stemivol"
 
*Unadjusted*
tab icu death30d, ro

*Adjusted*
logistic death30d i.icu `coV', vce(cluster hospid)
margins r.icu, contrast

*IV*
ivregress 2sls death30d (i.icu = diffdist) `coV', first vce(cluster hospid)
margins icu

*Caterpillar Plot (Figure 1)*

use stemi_hosplev, clear

scatter icurate hosp_rank, xlabel(0(250)1750) msymbol (circle_hollow) ///
 xtitle(Hospitals Ranked by ICU Admission Rate for STEMI) ///
 ytitle("ICU Admission Rate" "for STEMI (%)", orientation(horizontal) ///
 justification(center)) ylabel(0(20)100, angle(0) noticks nogrid) ///
 graphregion(color(white)) scheme(plotplainblind)

*Subgroup Analyses (Figure 2)*

use stemi, clear

*No respiratory failure or shock*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if respfail == 0 & shock == 0, vce(cluster hospid)

*0 or 1+ organ failures*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if totorgfA == 0, vce(cluster hospid) 

ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if totorgfA > 0, vce(cluster hospid)

*White or non-white race*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if racecat == 1, vce(cluster hospid)

ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if racecat == 2 | racecat == 3, vce(cluster hospid)

*Urban or rural residence*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if nchs == 1 | nchs == 2 | nchs == 3 | ///
 nchs == 4, vce(cluster hospid)

ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if nchs == 5 | nchs == 6, vce(cluster hospid)

*Aged 65-79 or 80+*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if age2 < 80, vce(cluster hospid)

ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if age2 >= 80, vce(cluster hospid)

*Patients without palliative care*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if palli == 0, vce(cluster hospid)

*Admitted to PCI-capable hospital*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if hospcath > 5, vce(cluster hospid)

*By intermediate care*
ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if intermadmits <= 5, vce(cluster hospid)

ivregress 2sls death30d (i.icu = diffdist) age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol if intermadmits > 5, vce(cluster hospid)

*Two-stage residual inclusion model (Non-linear IV model)*
capture program drop twosri
program twosri, eclass
tempname b V
capture drop Xuhat

glm icu diffdist age2 i.sex i.racecat i.nchs i.catinc i.reg, ///
 family(binomial) link(logit) vce(cluster hospid)
glm, eform
predict Xuhat, response

glm death30d i.icu Xuhat age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol, family(binomial) link(logit) vce(cluster hospid)
glm, eform
margins r.icu, contrast

matrix `b' = e(b)
ereturn post `b'
end

bootstrap _b, reps(3000) seed(21212) nodots nowarn: twosri
glm, eform

*Estimating Probability of ICU Admission by Differential Distance*

/* The dd10 variable represents the differential distance in 10-mile increments. */

logistic icu dd10 age2 i.sex i.racecat i.nchs i.catinc totorgfA i.elix1 i.elix3 ///
 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 i.elix10 i.elix11 i.elix12 ///
 i.elix13 i.elix17 i.elix18 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 ///
 i.elix24 i.elix25 i.elix26 i.elix29 i.elix30 i.cath i.cabg i.lytics ///
 i.invmechvent i.nippv i.reg teachperc hospbd icuperc medicaid nurserat ///
 stemivol, vce(cluster hospid)
test dd10

*Estimating Proportions of Marginal Subgroups*

gen label_marg_pop = .
foreach num of numlist 1/7 {
replace label_marg_pop = `num' in `num'
}
label define flabel_marg_pop 1 "Hospital compliers" 2 "Prop of ICU compliers" ///
 3 "Prop of ICU always" 4 "Prop of ICU never" 5 "ICU Compliers" 6 "ICU Always" 7 "ICU Never"
label values label_marg_pop flabel_marg_pop

recode icu (0 = 1) (1 = 0), gen(nonicu)
gen marg_pop = .
local i = 1
qui reg stemiicucat if diffdist < 6.8
local cons1 = _b[_cons]
qui reg stemiicucat if diffdist >= 6.8
local hcomplier = `cons1'-_b[_cons]
replace marg_pop = `hcomplier' in `i++'
qui reg icu if diffdist < 6.8 & stemiicucat == 1
local cons2 = _b[_cons]
qui reg icu if diffdist >= 6.8 & stemiicucat == 0
local icucomplier = `cons2'-_b[_cons]
replace marg_pop = `icucomplier' in `i++'
qui reg icu if diffdist >= 6.8 & stemiicucat == 0
local icualways = _b[_cons]
replace marg_pop = `icualways' in `i++'
qui reg nonicu if diffdist < 6.8 & stemiicucat == 1
local icunever = _b[_cons]
replace marg_pop = `icunever' in `i++'
di `icucomplier'+`icualways'+`icunever'
replace marg_pop = `hcomplier'*`icucomplier' in `i++'
replace marg_pop = `hcomplier'*`icualways' in `i++'
replace marg_pop = `hcomplier'*`icunever' in `i++'
di (`hcomplier'*`icucomplier')+(`hcomplier'*`icualways')+(`hcomplier'*`icunever')

*Characterizing marginal subgroups*

gen label_marginal = .
foreach num of numlist 1/18 {
replace label_marginal = `num' in `num'
}
label define flabel_marginal 1 "Age 65-74" 2 "Age 75-84" 3 "Age 85+" 4 "Male" 5 "Female" ///
 6 "White" 7 "Non-white" 8 "Rural" 9 "Urban" 10 "Northeast" 11 "Midwest" 12 "South" 13 "West" ///
 14 "< 40,000" 15 "40-100,000" 16 "> 100,000" 17 "No organ failures" 18 "1+ Organ failures"
label values label_marginal flabel_marginal

recode racecat (1=1) (2 3 = 2), gen(race2cat)
recode orgfail (0=1) (1 2 = 2), gen(orgfail2)
recode nchs (5 6 = 0) (1 2 3 4 = 1), gen(urban)

gen ratio_marginal = .
local k = 1
forvalues age = 1/3 {
qui reg icu if agecat == `age' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if agecat == `age' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
qui reg icu if diffdist < 6.8
local cons2 = _b[_cons]
qui reg icu if diffdist >= 6.8
local firststage_pop = `cons2'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}
forvalues sexcat = 1/2 {
qui reg icu if sex == `sexcat' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if sex == `sexcat' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}
forvalues racecat = 1/2 {
qui reg icu if race2cat == `racecat' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if race2cat == `racecat' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}
forvalues urb = 0/1 {
qui reg icu if urban == `urb' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if urban == `urb' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}
forvalues reg = 1/4 {
qui reg icu if reg4 == `reg' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if reg4 == `reg' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}
forvalues inc = 1/3 {
qui reg icu if catinc == `inc' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if catinc == `inc' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}
forvalues orgfail = 1/2 {
qui reg icu if orgfail2 == `orgfail' & diffdist < 6.8
local cons1 = _b[_cons]
qui reg icu if orgfail2 == `orgfail' & diffdist >= 6.8
local firststage_group = `cons1'-_b[_cons]
replace ratio_marginal = `firststage_group'/`firststage_pop' in `k++'
}

*Estimating ICU admission and 30-day mortality by age*

capture drop Xuhat
glm icu diffdist age2 i.sex i.racecat i.nchs i.catinc i.reg, ///
 family(binomial) link(logit) vce(cluster hospid)
glm, eform
predict Xuhat, response

glm death30d i.icu Xuhat age2 i.sex i.racecat i.nchs i.catinc ///
 totorgfA i.elix1 i.elix3 i.elix4 i.elix5 i.elix6 i.elix7 i.elix8 i.elix9 ///
 i.elix10 i.elix11 i.elix12 i.elix13 i.elix17 i.elix18 ///
 i.elix19 i.elix20 i.elix21 i.elix22 i.elix23 i.elix24 i.elix25 i.elix26 ///
 i.elix29 i.elix30 i.cath i.cabg i.lytics i.invmechvent i.nippv i.reg teachperc ///
 hospbd icuperc medicaid nurserat stemivol, family(binomial) link(logit) vce(cluster hospid)
margins icu, at(age2=(65 (5) 90))
marginsplot, scheme(plotplainblind)

log close
