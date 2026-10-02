

===== 01-01-welcome.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Welcome</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <div>
      [svg]
    </div>
    <span>PawsitiveSync</span>
  </div>
  <div>
    <div>
      <div>
        [svg]
      </div>
      <div>
        <div>Morning insulin · Miso</div>
        <div>Given by Sara at 8:02 AM</div>
      </div>
      <div>S</div>
    </div>
    <div>
      <div></div>
      <div>
        <div>Fluids · 100 ml</div>
        <div>Dan is on it · 1:00 PM</div>
      </div>
      <div>D</div>
    </div>
    <div>
      [svg]
      <div>Benazepril: 4 doses left. Refill by Tue.</div>
    </div>
  </div>
  <div>
    <h1>Every dose, seen by everyone who cares for them.</h1>
    <p>One shared schedule for your household. No missed doses, and none given twice.</p>
    <div>
      <a href="Onb-Pet.dc.html">Get started</a>
      <a href="Household.dc.html">I was invited to a household</a>
    </div>
  </div>
</div>
</x-dc>
</body></html>


===== 02-02-pet-basics.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Pet basics</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Main.dc.html" aria-label="Back">
      [svg]
    </a>
    <div><div></div></div>
    <span>1 of 5</span>
  </div>
  <h1>Who are we caring for?</h1>
  <p>Start with one pet. You can add the rest later.</p>
  <div>
    <button type="button" aria-label="Add photo">
      [svg]
    </button>
    <div>
      <div>Add a photo</div>
      <div>Helps sitters spot the right pet</div>
    </div>
  </div>
  <div>
    <label for="pname">Name</label>
    <input id="pname" value="Miso">
  </div>
  <div>
    <div>Species</div>
    <div>
      <button type="button" aria-pressed="true">Cat</button>
      <button type="button" aria-pressed="false">Dog</button>
      <button type="button" aria-pressed="false">Rabbit</button>
      <button type="button" aria-pressed="false">Other</button>
    </div>
  </div>
  <div>
    <div>
      <div>Age</div>
      <div>
        <button type="button" aria-label="Decrease age">−</button>
        <span>12 yrs</span>
        <button type="button" aria-label="Increase age">+</button>
      </div>
    </div>
    <div>
      <label for="pweight">Weight (optional)</label>
      <div>
        <input id="pweight" value="4.6">
        <span>kg</span>
      </div>
    </div>
  </div>
  <a href="Onb-Conditions.dc.html">Continue</a>
</div>
</x-dc>
</body></html>


===== 03-03-conditions-quiz.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Conditions quiz</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Onb-Pet.dc.html" aria-label="Back">
      [svg]
    </a>
    <div><div></div></div>
    <span>2 of 5</span>
  </div>
  <h1>What is Miso being treated for?</h1>
  <p>Pick all that apply. We'll set up a starter schedule for each.</p>
  <div role="group" aria-label="Conditions">
    <button type="button" aria-pressed="true">
      <span><span>Diabetes</span><span>Insulin, usually twice a day</span></span>
      <span>[svg]</span>
    </button>
    <button type="button" aria-pressed="true">
      <span><span>Kidney disease</span><span>Fluids, blood pressure tablets</span></span>
      <span>[svg]</span>
    </button>
    <button type="button" aria-pressed="false">
      <span><span>Thyroid</span><span>Daily tablets or gel</span></span>
      <span></span>
    </button>
    <button type="button" aria-pressed="false">
      <span><span>Heart condition</span><span>Several meds at set times</span></span>
      <span></span>
    </button>
    <button type="button" aria-pressed="false">
      <span><span>Arthritis or pain</span><span>Daily pain relief, supplements</span></span>
      <span></span>
    </button>
    <button type="button" aria-pressed="false">
      <span><span>Preventatives only</span><span>Flea, tick, heartworm</span></span>
      <span></span>
    </button>
  </div>
  <a href="Onb-Caregivers.dc.html">Continue with 2 selected</a>
</div>
</x-dc>
</body></html>


===== 04-04-caregivers-insight.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Caregivers</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Onb-Conditions.dc.html" aria-label="Back">
      [svg]
    </a>
    <div><div></div></div>
    <span>3 of 5</span>
  </div>
  <h1>Who else gives Miso medication?</h1>
  <p>Pick everyone who helps.</p>
  <div role="group" aria-label="Caregivers">
    <button type="button" aria-pressed="false">Just me<span></span></button>
    <button type="button" aria-pressed="true">Partner or family<span>[svg]</span></button>
    <button type="button" aria-pressed="true">Pet sitter or walker<span>[svg]</span></button>
    <button type="button" aria-pressed="false">Roommates<span></span></button>
  </div>
  <div>
    <div>
      <div>
        <div>You</div>
        <div>P</div>
        <div>S</div>
      </div>
      <span>Three people, one schedule</span>
    </div>
    <p>When more than one person gives meds, doses get missed or given twice. Here, everyone sees who gave what, the moment it happens.</p>
  </div>
  <a href="Onb-Notifications.dc.html">Continue</a>
</div>
</x-dc>
</body></html>


===== 05-05-notification-priming.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Notification priming</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Onb-Caregivers.dc.html" aria-label="Back">
      [svg]
    </a>
    <div><div></div></div>
    <span>4 of 5</span>
  </div>
  <h1>Answer reminders from your lock screen</h1>
  <div>
    <div>
      <div>
        <div>
          <div></div>
          <span>PAWSITIVESYNC</span>
          <span>now</span>
        </div>
        <div>Miso's evening insulin</div>
        <div>2 units with food · due 8:00 PM</div>
      </div>
      <div>
        <div>Mark given</div>
        <div>Snooze 15 min</div>
      </div>
    </div>
    <div>
      <div>Sara gave Miso's insulin</div>
      <div>8:02 AM · You're all set this morning</div>
    </div>
  </div>
  <div>
    <div>
      [svg]
      <span>Mark a dose given without unlocking</span>
    </div>
    <div>
      [svg]
      <span>Know when someone else already gave it</span>
    </div>
    <div>
      [svg]
      <span>Get a refill heads-up before you run out</span>
    </div>
  </div>
  <div>
    <a href="Paywall.dc.html">Turn on reminders</a>
    <a href="Paywall.dc.html">Maybe later</a>
  </div>
</div>
</x-dc>
</body></html>


===== 06-06-trial-paywall.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Trial paywall</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Today.dc.html" aria-label="Close and continue free">
      [svg]
    </a>
    <a href="Today.dc.html">Restore</a>
  </div>
  <h1>Care for Miso together.</h1>
  <p>Try every Pro feature free. Cancel anytime.</p>
  <div>
    <div>
      <div>
        <div>[svg]</div>
        <div></div>
      </div>
      <div><div>Today</div><div>Household sync, refill alerts, vet reports, unlimited pets</div></div>
    </div>
    <div>
      <div>
        <div>[svg]</div>
        <div></div>
      </div>
      <div><div>Day 5</div><div>We remind you before the trial ends</div></div>
    </div>
    <div>
      <div><div></div></div>
      <div><div>Day 7</div><div>Your plan starts. Cancel before and pay nothing.</div></div>
    </div>
  </div>
  <div role="radiogroup" aria-label="Plan">
    <button type="button" role="radio" aria-checked="true">
      <span></span>
      <span><span>Yearly</span><span>$29.99 per year</span></span>
      <span>$2.50/mo</span>
      <span>Save 50%</span>
    </button>
    <button type="button" role="radio" aria-checked="false">
      <span></span>
      <span>Monthly</span>
      <span>$4.99/mo</span>
    </button>
  </div>
  <div>
    <a href="Today.dc.html">Start 7-day free trial</a>
    <p>No charge today. Then $29.99 per year.</p>
    <div>
      <a href="#">Terms</a><a href="#">Privacy</a><a href="Today.dc.html">Continue free with 1 pet</a>
    </div>
  </div>
</div>
</x-dc>
</body></html>


===== 07-07-today.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Today</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <div>
      <div>Friday, October 2</div>
      <h1>Today</h1>
    </div>
    <a href="Household.dc.html" aria-label="Household, 3 people in sync">
      <div>S</div>
      <div>D</div>
      <div>You</div>
    </a>
  </div>
  <div>
    <div><span>3 of 6 given</span><span>Next: Fluids at 1:00 PM</span></div>
    <div>
      <div></div><div></div><div></div><div></div><div></div><div></div>
    </div>
  </div>
  <div role="tablist" aria-label="Filter by pet">
    <button type="button" role="tab" aria-selected="true">All pets</button>
    <button type="button" role="tab" aria-selected="false">Miso</button>
    <button type="button" role="tab" aria-selected="false">Juniper</button>
  </div>
  <a href="Med-Detail.dc.html">
    [svg]
    <span><span>Benazepril is running low</span><span>4 doses left · lasts until Tue</span></span>
    <span>Refill</span>
  </a>
  <div>MORNING</div>
  <div>
    <a href="Double-Dose-Guard.dc.html">
      <span>[svg]</span>
      <span><span>Insulin · 2 units</span><span>Miso · Sara, 8:02 AM</span></span>
      <span>S</span>
    </a>
    <div>
      <span>[svg]</span>
      <span><span>Benazepril · 2.5 mg</span><span>Miso · Sara, 8:04 AM</span></span>
      <span>S</span>
    </div>
    <div>
      <span>[svg]</span>
      <span><span>Joint supplement</span><span>Juniper · Dan, 8:30 AM</span></span>
      <span>D</span>
    </div>
  </div>
  <div>AFTERNOON</div>
  <div>
    <span></span>
    <span><span>Fluids · 100 ml</span><span>Miso · due 1:00 PM</span></span>
    <a href="Log-Dose.dc.html">Mark given</a>
  </div>
  <div>EVENING</div>
  <div>
    <span></span>
    <span><span>Insulin · 2 units</span><span>Miso · 8:00 PM with food · Dan</span></span>
  </div>
  <nav aria-label="Tabs">
    <a href="Today.dc.html" aria-current="page">[svg]Today</a>
    <a href="Pet-Profile.dc.html">[svg]Pets</a>
    <a href="Household.dc.html">[svg]Household</a>
    <a href="Vet-Report.dc.html">[svg]Reports</a>
  </nav>
</div>
</x-dc>
</body></html>


===== 08-08-log-dose-sheet.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Log dose</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <div>Friday, October 2</div>
    <div>Today</div>
  </div>
  <div></div>
  <div role="dialog" aria-label="Log fluids for Miso">
    <div></div>
    <div>
      <div>
        <h2>Log fluids</h2>
        <div>Miso · subcutaneous · due 1:00 PM</div>
      </div>
      <a href="Today.dc.html" aria-label="Close">[svg]</a>
    </div>
    <div>
      <span>Amount</span>
      <div>
        <button type="button" aria-label="Less">−</button>
        <span>100 ml</span>
        <button type="button" aria-label="More">+</button>
      </div>
    </div>
    <div>When</div>
    <div role="radiogroup" aria-label="When">
      <button type="button" role="radio" aria-checked="true">Now · 1:06 PM</button>
      <button type="button" role="radio" aria-checked="false">Earlier…</button>
    </div>
    <div>Given by</div>
    <div role="radiogroup" aria-label="Given by">
      <button type="button" role="radio" aria-checked="true">
        <span>You</span>
        <span>You</span>
      </button>
      <button type="button" role="radio" aria-checked="false">
        <span>S</span>
        <span>Sara</span>
      </button>
      <button type="button" role="radio" aria-checked="false">
        <span>D</span>
        <span>Dan</span>
      </button>
    </div>
    <div>How did it go? <span>Optional</span></div>
    <div>
      <button type="button" aria-pressed="true">Went smoothly</button>
      <button type="button" aria-pressed="false">Partial dose</button>
      <button type="button" aria-pressed="false">Vomited</button>
      <button type="button" aria-pressed="false">Low appetite</button>
      <button type="button" aria-label="Add a note">+ Note</button>
    </div>
    <a href="Today.dc.html">Log dose</a>
    <a href="Today.dc.html">Skip this dose</a>
  </div>
</div>
</x-dc>
</body></html>


===== 09-09-double-dose-guard.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Double-dose guard</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <div>Friday, October 2</div>
    <div>Today</div>
  </div>
  <div></div>
  <div role="alertdialog" aria-label="Dose already given">
    <div></div>
    <div>
      [svg]
    </div>
    <h2>Sara already gave this dose</h2>
    <p>Miso's morning insulin was logged 6 minutes ago. Giving it again could cause dangerously low blood sugar.</p>
    <div>
      <span>S</span>
      <span><span>Insulin · 2 units</span><span>Given by Sara · 8:02 AM · with breakfast</span></span>
      <span>[svg]</span>
    </div>
    <a href="Today.dc.html">Got it, don't log</a>
    <a href="Log-Dose.dc.html">This is a separate dose</a>
    <p>Only log a second dose if your vet told you to.</p>
  </div>
</div>
</x-dc>
</body></html>


===== 10-10-lock-screen-actions.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Lock-screen actions</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <div>Friday, October 2</div>
    <div>7:58</div>
  </div>
  <div>
    <div>
      <div>
        <div></div>
        <span>PAWSITIVESYNC</span>
        <span>now</span>
      </div>
      <div>Miso's evening insulin is due</div>
      <div>2 units with food at 8:00 PM. Dan is on tonight.</div>
    </div>
  </div>
  <div>
    <div>Mark given[svg]</div>
    <div>Snooze 15 minutes[svg]</div>
    <div>Someone else gave it[svg]</div>
  </div>
  <div>
    <div></div>
    <div>
      <div>Sara gave Juniper's supplement</div>
      <div>Evening dose done · 7:41 PM</div>
    </div>
  </div>
  <div></div>
</div>
</x-dc>
</body></html>


===== 11-11-medication-refill.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Medication detail</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Today.dc.html">[svg]Today</a>
    <a href="Schedule-Rule.dc.html">Edit</a>
  </div>
  <div>
    <h1>Benazepril</h1>
    <div>2.5 mg tablet · Miso · kidney support</div>
  </div>
  <div>
    <div>
      <span>SUPPLY · LOW</span>
      <span>of 30</span>
    </div>
    <div>
      <span>4</span>
      <span>doses left</span>
    </div>
    <div><div></div></div>
    <div>Last dose <span>Tue, Oct 6</span> at this pace</div>
    <div>
      <button type="button">I refilled it</button>
      <button type="button">[svg]Call vet</button>
    </div>
  </div>
  <div>SCHEDULE</div>
  <div>
    <div><span>Dose</span><span>1 tablet</span></div>
    <div><span>When</span><span>Daily, 8:00 AM</span></div>
    <div><span>If not logged</span><span>Ping Sara after 30 min</span></div>
  </div>
  <div>
    <span>LAST 7 DAYS</span>
    <span>29 of 30 on time this month</span>
  </div>
  <div>
    <div>
      <div><div></div><div>Sat</div></div>
      <div><div></div><div>Sun</div></div>
      <div><div></div><div>Mon</div></div>
      <div><div></div><div>Tue</div></div>
      <div><div></div><div>Wed</div></div>
      <div><div></div><div>Thu</div></div>
      <div><div></div><div>Fri</div></div>
    </div>
    <div>
      <div><span>Today · 8:04 AM</span><span>Sara</span></div>
      <div><span>Thu · 8:11 AM</span><span>Dan</span></div>
      <div><span>Wed · 9:40 AM <span>· 1h 40m late</span></span><span>You</span></div>
    </div>
  </div>
</div>
</x-dc>
</body></html>


===== 12-12-adaptive-schedule.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Adaptive schedule</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Med-Detail.dc.html" aria-label="Back">[svg]</a>
    <span>New medication</span>
    <span>2/3</span>
  </div>
  <div>Heartworm chew · Juniper</div>
  <h1>When should the next dose be due?</h1>
  <div><span>Repeats</span><span>Every month</span></div>
  <div role="radiogroup" aria-label="Timing rule">
    <button type="button" role="radio" aria-checked="true">
      <span></span>
      <span><span>From the last dose <span>Recommended</span></span><span>Gave it late? The next one counts from when it was actually given.</span></span>
    </button>
    <button type="button" role="radio" aria-checked="false">
      <span></span>
      <span><span>Same date every month</span><span>Stays on the 1st, even after a late dose.</span></span>
    </button>
  </div>
  <div>
    <div>HOW THIS PLAYS OUT</div>
    <div>
      <div></div>
      <div><div></div><div>Sep 1</div><div>was due</div></div>
      <div><div></div><div>Sep 4</div><div>given late</div></div>
      <div><div></div><div>Oct 4</div><div>next due</div></div>
      <div><div></div><div>Nov 4</div><div>then</div></div>
    </div>
  </div>
  <div>
    <div><span>Remind at</span><span>9:00 AM</span></div>
    <div><span>In the box</span><span>6 chews</span></div>
  </div>
  <a href="Today.dc.html">Save medication</a>
</div>
</x-dc>
</body></html>


===== 13-13-household-activity.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Household</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <h1>Household</h1>
    <div>Everyone caring for Miso and Juniper</div>
  </div>
  <div>
    <div>
      <span>You</span>
      <span>You</span><span>Owner</span>
    </div>
    <div>
      <span>S<span></span></span>
      <span><span>Sara</span><span>Active now</span></span><span>Caregiver</span>
    </div>
    <div>
      <span>D</span>
      <span><span>Dan</span><span>On duty tonight</span></span><span>Caregiver</span>
    </div>
    <div>
      <span>P</span>
      <span><span>Priya</span><span>Oct 5 – Oct 12</span></span><span>Sitter</span>
    </div>
  </div>
  <a href="Paywall-Invite.dc.html">[svg]Invite someone</a>
  <div>
    <span>ACTIVITY · TODAY</span>
    <span>Filter</span>
  </div>
  <div>
    <div>
      <span>S</span>
      <span><span>Sara</span> gave Miso <span>Insulin · 2 units</span><span>8:02 AM</span></span>
    </div>
    <div>
      <span>S</span>
      <span><span>Sara</span> gave Miso <span>Benazepril</span><span>8:04 AM</span></span>
    </div>
    <div>
      <span>D</span>
      <span><span>Dan</span> noted for Miso<span>Vomited a little after breakfast</span><span>8:20 AM</span></span>
    </div>
  </div>
  <nav aria-label="Tabs">
    <a href="Today.dc.html">[svg]Today</a>
    <a href="Pet-Profile.dc.html">[svg]Pets</a>
    <a href="Household.dc.html" aria-current="page">[svg]Household</a>
    <a href="Vet-Report.dc.html">[svg]Reports</a>
  </nav>
</div>
</x-dc>
</body></html>


===== 14-14-hard-paywall-invite.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Household paywall</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <div>Household</div>
  </div>
  <div></div>
  <div role="dialog" aria-label="Household sync is part of Pro">
    <div></div>
    <div>
      <span>You</span>
      <span>S</span>
      <span>[svg]</span>
    </div>
    <h2>Bring Sara onto Miso's schedule</h2>
    <p>Household sync is part of Pro. Everyone sees each dose the moment it's given.</p>
    <div>
      <div><span></span><span>FREE</span><span>PRO</span></div>
      <div><span>Caregivers</span><span>Just you</span><span>Everyone</span></div>
      <div><span>Pets</span><span>1</span><span>Unlimited</span></div>
      <div><span>Refill alerts</span><span>–</span><span>Included</span></div>
      <div><span>Vet PDF report</span><span>–</span><span>Included</span></div>
    </div>
    <div role="radiogroup" aria-label="Plan">
      <button type="button" role="radio" aria-checked="true"><span>Yearly · Save 50%</span><span>$29.99/yr</span></button>
      <button type="button" role="radio" aria-checked="false"><span>Monthly</span><span>$4.99/mo</span></button>
    </div>
    <a href="Invite.dc.html">Try Pro free for 7 days</a>
    <a href="Household.dc.html">Not now</a>
  </div>
</div>
</x-dc>
</body></html>


===== 15-15-invite-sitter-access.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Invite to household</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Household.dc.html" aria-label="Back">[svg]</a>
    <span>Invite</span>
    <span></span>
  </div>
  <h1>Who are you inviting?</h1>
  <div role="radiogroup" aria-label="Role">
    <button type="button" role="radio" aria-checked="false">
      <span></span>
      <span><span>Caregiver</span><span>Partner or family. Sees and logs everything.</span></span>
    </button>
    <button type="button" role="radio" aria-checked="true">
      <span></span>
      <span><span>Sitter</span><span>Only what they need, for set dates. Access ends on its own.</span></span>
    </button>
  </div>
  <div>
    <div>
      [svg]
      <span>Access</span><span>Oct 5 – Oct 12</span>
    </div>
    <div>
      [svg]
      <span>Pets</span><span>Miso, Juniper</span>
    </div>
    <div>
      [svg]
      <span>Can see</span><span>Today's doses, notes</span>
    </div>
    <label>
      [svg]
      <span>Tell me when they log a dose</span>
      <input type="checkbox" checked="" aria-label="Tell me when they log a dose">
      <span aria-hidden="true"><span></span></span>
    </label>
  </div>
  <div>
    [svg]
    <span><span>Invite link ready</span><span>Works once · expires in 48 hours</span></span>
    <button type="button">Copy</button>
  </div>
  <a href="Household.dc.html">[svg]Share invite</a>
</div>
</x-dc>
</body></html>


===== 16-16-pet-profile.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Pet profile</title>
</head>
<body>
<x-dc>
<div>
  <div role="tablist" aria-label="Pets">
    <button type="button" role="tab" aria-selected="true">Miso</button>
    <button type="button" role="tab" aria-selected="false">Juniper</button>
    <button type="button" aria-label="Add pet">[svg]</button>
  </div>
  <div>
    <div>M</div>
    <div>
      <h1>Miso</h1>
      <div>Domestic shorthair · 12 yrs · female</div>
    </div>
  </div>
  <div>
    <span>Diabetes</span>
    <span>Kidney disease</span>
  </div>
  <div>
    <div><div>Weight</div><div>4.6 kg</div></div>
    <div><div>Daily meds</div><div>3</div></div>
    <div><div>On time</div><div>97%</div></div>
  </div>
  <div>
    <div>
      <span>Weight · 90 days</span>
      <span>−0.3 kg</span>
    </div>
    [svg]
    <div><span>Jul 4 · 4.9</span><span>Oct 2 · 4.6</span></div>
  </div>
  <div>
    <div>This week</div>
    <div><span>Vomited</span><span>2 times · last today</span></div>
    <div><span>Appetite</span><span>Normal</span></div>
  </div>
  <a href="Vet-Report.dc.html">[svg]Prepare vet report</a>
  <nav aria-label="Tabs">
    <a href="Today.dc.html">[svg]Today</a>
    <a href="Pet-Profile.dc.html" aria-current="page">[svg]Pets</a>
    <a href="Household.dc.html">[svg]Household</a>
    <a href="Vet-Report.dc.html">[svg]Reports</a>
  </nav>
</div>
</x-dc>
</body></html>


===== 17-17-vet-pdf-report.html =====
<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<title>Vet report</title>
</head>
<body>
<x-dc>
<div>
  <div>
    <a href="Pet-Profile.dc.html" aria-label="Back">[svg]</a>
    <span>Vet report</span>
    <span></span>
  </div>
  <h1>Ready for Miso's checkup</h1>
  <div role="radiogroup" aria-label="Date range">
    <button type="button" role="radio" aria-checked="true">30 days</button>
    <button type="button" role="radio" aria-checked="false">60 days</button>
    <button type="button" role="radio" aria-checked="false">90 days</button>
  </div>
  <div>
    <div>
      <div>
        <span>Miso · Care report</span>
        <span>Sep 3 – Oct 2, 2026</span>
      </div>
      <div>Cat · 12 yrs · Diabetes, kidney disease · [VET CLINIC NAME]</div>
      <div>DOSES GIVEN</div>
      <div>
        <div><span>Insulin 2 u</span><span><span></span></span><span>59/60</span></div>
        <div><span>Benazepril</span><span><span></span></span><span>29/30</span></div>
        <div><span>Fluids 100 ml</span><span><span></span></span><span>28/30</span></div>
      </div>
      <div>WEIGHT</div>
      [svg]
      <div>SYMPTOM NOTES</div>
      <div>Vomited ×4 (2 this week) · Low appetite ×1</div>
    </div>
  </div>
  <div>
    <div>Dose log, weight, symptoms[svg]</div>
    <label>Show who gave each dose
      <input type="checkbox" checked="" aria-label="Show who gave each dose">
      <span aria-hidden="true"><span></span></span>
    </label>
  </div>
  <div>
    <button type="button">[svg]Email vet</button>
    <button type="button">[svg]Export PDF</button>
  </div>
</div>
</x-dc>
</body></html>