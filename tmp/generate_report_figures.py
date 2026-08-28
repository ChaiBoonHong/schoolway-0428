from __future__ import annotations

import math
import textwrap
from html import escape
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUT = Path(r"D:\OneDrive - Universiti Tunku Abdul Rahman\UTAR FYP\3. FYP2\Generated Figures")
OUT.mkdir(parents=True, exist_ok=True)

NAVY = "#0A2342"
BLUE = "#0077B6"
CYAN = "#00B4D8"
PALE = "#EAF7FC"
PALE2 = "#F5FBFE"
GREEN = "#2E7D32"
ORANGE = "#F59E0B"
RED = "#C62828"
GRAY = "#52606D"
LIGHT_GRAY = "#E6EDF2"
WHITE = "#FFFFFF"
BLACK = "#15202B"

FONT = r"C:\Windows\Fonts\arial.ttf"
BOLD = r"C:\Windows\Fonts\arialbd.ttf"


class Figure:
    def __init__(self, name: str, width: int, height: int, title: str, subtitle: str = ""):
        self.name = name
        self.w = width
        self.h = height
        self.scale = 2
        self.image = Image.new("RGB", (width * self.scale, height * self.scale), "white")
        self.draw = ImageDraw.Draw(self.image)
        self.svg: list[str] = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
            '<rect width="100%" height="100%" fill="#FFFFFF"/>',
            '<defs><marker id="arrow" markerWidth="10" markerHeight="7" refX="9" refY="3.5" orient="auto"><polygon points="0 0, 10 3.5, 0 7" fill="#0A2342"/></marker></defs>',
        ]
        self.text(width / 2, 42, title, 30, BOLD, NAVY, anchor="mm")
        if subtitle:
            self.text(width / 2, 78, subtitle, 16, FONT, GRAY, anchor="mm")
        self.line(60, 100, width - 60, 100, CYAN, 3)

    def _font(self, size: int, bold: bool = False):
        return ImageFont.truetype(BOLD if bold else FONT, size * self.scale)

    def text(self, x, y, text, size=18, font=FONT, fill=BLACK, anchor="mm", max_width=None, line_gap=1.2):
        bold = font == BOLD
        pil_font = self._font(size, bold)
        lines = [text]
        if max_width:
            words = text.split()
            lines, current = [], ""
            for word in words:
                candidate = f"{current} {word}".strip()
                if self.draw.textlength(candidate, font=pil_font) / self.scale <= max_width or not current:
                    current = candidate
                else:
                    lines.append(current)
                    current = word
            if current:
                lines.append(current)
        line_h = size * line_gap
        total_h = line_h * len(lines)
        if anchor.endswith("m"):
            start_y = y - total_h / 2 + line_h / 2
        elif anchor.endswith("b"):
            start_y = y - total_h + line_h / 2
        else:
            start_y = y + line_h / 2
        text_anchor = "mm" if anchor.startswith("m") else ("lm" if anchor.startswith("l") else "rm")
        svg_anchor = "middle" if anchor.startswith("m") else ("start" if anchor.startswith("l") else "end")
        for i, line in enumerate(lines):
            yy = start_y + i * line_h
            self.draw.text((x * self.scale, yy * self.scale), line, font=pil_font, fill=fill, anchor=text_anchor)
            self.svg.append(
                f'<text x="{x}" y="{yy + size * 0.34}" font-family="Arial" font-size="{size}" font-weight="{700 if bold else 400}" fill="{fill}" text-anchor="{svg_anchor}">{escape(line)}</text>'
            )

    def rect(self, x, y, w, h, fill=WHITE, outline=NAVY, radius=14, width=2, label=None, size=18, bold=False, label_fill=BLACK):
        box = tuple(int(v * self.scale) for v in (x, y, x + w, y + h))
        self.draw.rounded_rectangle(box, radius=radius * self.scale, fill=fill, outline=outline, width=width * self.scale)
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{outline}" stroke-width="{width}"/>')
        if label:
            self.text(x + w / 2, y + h / 2, label, size, BOLD if bold else FONT, label_fill, "mm", w - 24)

    def line(self, x1, y1, x2, y2, fill=NAVY, width=2, arrow=False, dash=None):
        self.draw.line((x1 * self.scale, y1 * self.scale, x2 * self.scale, y2 * self.scale), fill=fill, width=width * self.scale)
        dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
        marker = ' marker-end="url(#arrow)"' if arrow else ""
        self.svg.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{fill}" stroke-width="{width}"{dash_attr}{marker}/>' )
        if arrow:
            angle = math.atan2(y2 - y1, x2 - x1)
            s = 12
            p1 = (x2 - s * math.cos(angle - 0.5), y2 - s * math.sin(angle - 0.5))
            p2 = (x2 - s * math.cos(angle + 0.5), y2 - s * math.sin(angle + 0.5))
            self.draw.polygon([(x2*self.scale,y2*self.scale),(p1[0]*self.scale,p1[1]*self.scale),(p2[0]*self.scale,p2[1]*self.scale)], fill=fill)

    def arrow(self, x1, y1, x2, y2, label=None):
        self.line(x1, y1, x2, y2, NAVY, 2, True)
        if label:
            self.text((x1+x2)/2, (y1+y2)/2-12, label, 14, FONT, GRAY, "mm", abs(x2-x1)-10 if abs(x2-x1)>80 else 180)

    def diamond(self, cx, cy, w, h, label, fill="#FFF8E1"):
        pts = [(cx,cy-h/2),(cx+w/2,cy),(cx,cy+h/2),(cx-w/2,cy)]
        self.draw.polygon([(x*self.scale,y*self.scale) for x,y in pts], fill=fill, outline=NAVY)
        self.svg.append(f'<polygon points="{" ".join(f"{x},{y}" for x,y in pts)}" fill="{fill}" stroke="{NAVY}" stroke-width="2"/>')
        self.text(cx,cy,label,15,BOLD,NAVY,"mm",w*0.65)

    def actor(self, x, y, label):
        r=22
        self.draw.ellipse(((x-r)*self.scale,(y-r)*self.scale,(x+r)*self.scale,(y+r)*self.scale),outline=NAVY,width=3*self.scale)
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="white" stroke="{NAVY}" stroke-width="3"/>')
        self.line(x,y+r,x,y+95,NAVY,3)
        self.line(x-38,y+55,x+38,y+55,NAVY,3)
        self.line(x,y+95,x-38,y+145,NAVY,3)
        self.line(x,y+95,x+38,y+145,NAVY,3)
        self.text(x,y+180,label,18,BOLD,NAVY,"mm",190)

    def ellipse(self, cx, cy, w, h, label, fill=PALE):
        box=((cx-w/2)*self.scale,(cy-h/2)*self.scale,(cx+w/2)*self.scale,(cy+h/2)*self.scale)
        self.draw.ellipse(box,fill=fill,outline=BLUE,width=2*self.scale)
        self.svg.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{w/2}" ry="{h/2}" fill="{fill}" stroke="{BLUE}" stroke-width="2"/>')
        self.text(cx,cy,label,16,FONT,NAVY,"mm",w-30)

    def save(self):
        self.svg.append(f'<text x="{self.w-30}" y="{self.h-18}" font-family="Arial" font-size="12" fill="{GRAY}" text-anchor="end">SchoolWay FYP2</text>')
        self.svg.append("</svg>")
        self.image.save(OUT / f"{self.name}.png", dpi=(300,300), optimize=True)
        (OUT / f"{self.name}.svg").write_text("\n".join(self.svg), encoding="utf-8")


def top_down():
    f=Figure("Figure_3_4_Top_Down_System_Design",1800,1200,"SchoolWay Top-Down System Design","Functional decomposition aligned with the current implementation")
    f.rect(690,135,420,90,BLUE,BLUE,18,2,"SchoolWay Mobile Application",24,True,WHITE)
    modules=[("Authentication & Account",100),("Parent Module",440),("Driver Module",780),("Administrator Module",1120),("Shared Services",1460)]
    children={
        "Authentication & Account":["Email/password & Google sign-in","Role routing & pending assignment","Saved-account switching","Profile & preferences"],
        "Parent Module":["Linked children","Live bus map & ETA","Trip and boarding history","Notifications & preferences"],
        "Driver Module":["Route session control","GPS upload","NFC board/alight","Roster, emergency & incidents"],
        "Administrator Module":["Users, students & buses","Route planning & assignments","CSV import","Fleet monitoring & reports"],
        "Shared Services":["Firestore & Cloud Functions","FCM notifications","Google Maps & Routes","Hive offline/recovery"],
    }
    for label,x in modules:
        f.arrow(900,225,x+120,300)
        f.rect(x,300,240,80,PALE,BLUE,14,2,label,18,True,NAVY)
        for i,c in enumerate(children[label]):
            y=440+i*155
            f.arrow(x+120,380 if i==0 else y-75,x+120,y)
            f.rect(x,y,240,80,WHITE,BLUE,12,2,c,15,False,NAVY)
    f.save()


def architecture():
    f=Figure("Figure_4_1_System_Architecture",1800,1250,"SchoolWay System Architecture","Layered Flutter, device, cloud, and external-service architecture")
    layers=[(130,"Presentation Layer",[(140,"Parent Module"),(470,"Driver Module"),(800,"Admin Module"),(1130,"Authentication / Role Gate"),(1460,"Responsive Theme & Localisation")]),
            (365,"Application Service Layer",[(140,"Account & Profile Services"),(470,"GPS / NFC / Boarding Services"),(800,"Route / ETA / Geofence Services"),(1130,"CSV / Notification Services"),(1460,"Diagnostics / Offline Queue")]),
            (600,"Data & Integration Layer",[(140,"Hive Local Storage"),(470,"Firebase Authentication"),(800,"Cloud Firestore (schoolway)"),(1130,"Firebase Cloud Messaging"),(1460,"Callable Cloud Functions")]),
            (835,"Device & External Services",[(140,"Android GPS"),(470,"Android NFC"),(800,"Google Maps"),(1130,"Google Routes API"),(1460,"Network / Push Delivery")])]
    for y,title,items in layers:
        f.rect(55,y-25,1690,175,PALE2,LIGHT_GRAY,18,2)
        f.text(80,y,title,20,BOLD,NAVY,"lt")
        for x,label in items:
            color=BLUE if y==130 else (CYAN if y==365 else ("#DDF4EA" if y==600 else "#FFF3D6"))
            f.rect(x,y+40,260,80,color,BLUE,14,2,label,16,True,NAVY)
    # Layer buses show many-to-many dependencies without implying false
    # one-to-one pairings between vertically aligned components.
    for top_y, bus_y, next_y, label in [
        (250, 325, 405, "UI invokes shared application services"),
        (485, 560, 640, "Services access authenticated data boundaries"),
        (720, 795, 875, "Adapters connect device and cloud capabilities"),
    ]:
        f.line(270,bus_y,1590,bus_y,BLUE,2)
        for x in [270,600,930,1260,1590]:
            f.line(x,top_y,x,bus_y,BLUE,2)
        f.arrow(900,bus_y,900,next_y)
        f.text(920,(bus_y+next_y)/2,label,13,FONT,GRAY,"lm",440)
    f.text(900,1125,"Authorization boundary: Firebase Auth UID + role + parent-child link + driver-bus/session assignment",18,BOLD,RED,"mm",1500)
    f.save()


def use_case():
    f=Figure("Figure_4_2_Use_Case_Diagram",1800,1350,"SchoolWay Use Case Diagram","Role-specific interactions with shared authentication")
    f.rect(365,125,1070,1110,PALE2,BLUE,24,3)
    f.text(900,160,"SchoolWay System Boundary",20,BOLD,NAVY,"mm")
    f.actor(180,300,"Parent")
    f.actor(180,720,"Driver")
    f.actor(1620,520,"Administrator")
    cases=[
        (900,220,"Authenticate / Sign Out"),(600,340,"View Linked Children"),(600,450,"Monitor Live Bus & ETA"),(600,560,"Review Trip / Boarding History"),(600,670,"Read Notifications & Preferences"),
        (900,420,"Start / Complete Route Session"),(900,530,"Upload GPS Location"),(900,640,"Scan NFC Board / Alight"),(900,750,"View Assigned Roster"),(900,860,"Create Emergency / Incident"),
        (1200,330,"Provision Users & Roles"),(1200,450,"Manage Students / Parents"),(1200,570,"Manage Buses / Drivers"),(1200,690,"Plan Routes / Assignments"),(1200,810,"CSV Import"),(1200,930,"Monitor Fleet / Reports"),(1200,1050,"Resolve Emergency Alerts")]
    for x,y,label in cases: f.ellipse(x,y,260,72,label)
    for y in [220,340,450,560,670]: f.line(240,355 if y==220 else 420,470,y,GRAY,2)
    for y in [220,420,530,640,750,860]: f.line(240,775,770,y,GRAY,2)
    for y in [220,330,450,570,690,810,930,1050]: f.line(1560,575,1330,y,GRAY,2)
    f.text(900,1195,"Roles are assigned by backend profile data; users do not select their own role.",17,BOLD,RED,"mm",1000)
    f.save()


def activity(name,title,actor_label,steps,decision_index=None,decision_label="Valid?",no_label="Stop and show a safe error"):
    h=max(1500,330+len(steps)*175)
    f=Figure(name,1400,h,title,"UML-style swimlane activity flow")
    f.rect(65,125,600,h-210,PALE2,LIGHT_GRAY,10,2)
    f.rect(735,125,600,h-210,PALE2,LIGHT_GRAY,10,2)
    f.rect(65,125,600,70,BLUE,BLUE,0,1,actor_label,22,True,WHITE)
    f.rect(735,125,600,70,NAVY,NAVY,0,1,"SchoolWay System",22,True,WHITE)
    cx=[365,1035]
    start_y=245
    f.draw.ellipse(((365-18)*2,(start_y-18)*2,(365+18)*2,(start_y+18)*2),fill=NAVY)
    f.svg.append(f'<circle cx="365" cy="{start_y}" r="18" fill="{NAVY}"/>')
    prev=(365,start_y)
    for i,(lane,label) in enumerate(steps):
        y=350+i*170
        x=cx[lane]
        if decision_index is not None and i==decision_index:
            f.arrow(prev[0],prev[1]+45,x,y-55)
            f.diamond(x,y,180,110,decision_label)
            # Failure branch terminates separately; the successful path
            # continues down the system lane.
            f.arrow(x-90,y,600,y,"No")
            f.rect(125,y-45,430,90,"#FFF1F0",RED,14,2,no_label,15,False,RED)
            f.arrow(340,y+45,340,y+105)
            f.draw.ellipse(((340-16)*2,(y+105-16)*2,(340+16)*2,(y+105+16)*2),fill=WHITE,outline=RED,width=3*2)
            f.draw.ellipse(((340-9)*2,(y+105-9)*2,(340+9)*2,(y+105+9)*2),fill=RED)
            f.svg.append(f'<circle cx="340" cy="{y+105}" r="16" fill="white" stroke="{RED}" stroke-width="3"/><circle cx="340" cy="{y+105}" r="9" fill="{RED}"/>')
            f.text(x+30,y+78,"Yes",14,BOLD,GREEN,"lm")
            prev=(x,y+55)
        else:
            f.arrow(prev[0],prev[1]+(18 if i==0 else 45),x,y-45)
            f.rect(x-235,y-45,470,90,WHITE,BLUE,14,2,label,17,False,NAVY)
            prev=(x,y)
    end_y=350+len(steps)*170
    f.arrow(prev[0],prev[1]+45,prev[0],end_y-20)
    f.draw.ellipse(((prev[0]-22)*2,(end_y-22)*2,(prev[0]+22)*2,(end_y+22)*2),fill=WHITE,outline=NAVY,width=3*2)
    f.draw.ellipse(((prev[0]-13)*2,(end_y-13)*2,(prev[0]+13)*2,(end_y+13)*2),fill=NAVY)
    f.svg.append(f'<circle cx="{prev[0]}" cy="{end_y}" r="22" fill="white" stroke="{NAVY}" stroke-width="3"/><circle cx="{prev[0]}" cy="{end_y}" r="13" fill="{NAVY}"/>')
    f.save()


def activities():
    activity("Figure_4_3_1_Authentication_Role_Routing_Activity","Authentication and Role Routing Activity","User",[(1,"Initialise Hive, Firebase and messaging"),(0,"Select saved account or sign-in method"),(0,"Submit email/password or Google identity"),(1,"Validate identity with Firebase Authentication"),(1,"Retrieve user profile by Auth UID"),(1,"Evaluate authoritative role"),(1,"Open Parent, Driver or Admin module")],5,"Role assigned?","Show pending-assignment or recoverable error")
    activity("Figure_4_3_2_Admin_Data_Route_Preparation_Activity","Administrator Data and Route Preparation Activity","Administrator",[(0,"Select management or CSV import function"),(0,"Enter users, students, buses or route stops"),(1,"Validate required fields and references"),(1,"Write valid records to Cloud Firestore"),(1,"Compute road geometry through Cloud Function"),(1,"Store Google geometry with ordered stops"),(0,"Assign driver, bus and students to route")],2,"Data valid?","Show row errors and return to input")
    activity("Figure_4_3_3_Driver_GPS_NFC_Activity","Driver Route, GPS and NFC Activity","Driver",[(0,"Review assigned bus, route and trip direction"),(0,"Start route session"),(1,"Verify driver-bus assignment and create session"),(1,"Enable session-bound GPS uploader"),(0,"Drive route and scan student NFC card"),(1,"Decode tag and match assigned student"),(1,"Determine next board or alight action"),(1,"Write event or queue eligible transient failure"),(0,"Review confirmation and roster status"),(0,"Complete route session")],5,"Student found?","Show unregistered-card warning; do not write")
    activity("Figure_4_3_4_Parent_Monitoring_Notification_Activity","Parent Monitoring and Notification Activity","Parent",[(0,"Authenticate and select linked child"),(1,"Verify parent-child and bus access"),(1,"Subscribe to route session, GPS and events"),(1,"Render authorised Google map and ETA"),(1,"Receive boarding, alighting or alert update"),(1,"Store notification in authorised inbox"),(0,"Review live status, history and notification"),(1,"Show stale/offline recovery state when needed")],1,"Access allowed?","Deny access and show a safe error")
    activity("Figure_4_3_5_Emergency_Alert_Activity","Emergency Alert Activity","Driver / Administrator",[(0,"Driver initiates emergency alert"),(1,"Capture driver, bus, session, time and location"),(1,"Validate assigned driver and bus"),(1,"Create emergency alert in Firestore"),(1,"Server identifies authorised recipients"),(1,"Notify linked families and Admin module"),(0,"Administrator reviews active alert"),(0,"Administrator records resolution"),(1,"Preserve alert and resolution history")],2,"Authorised?","Reject alert write and show an error")


def database():
    f=Figure("Figure_4_4_Firestore_Data_Model",2000,1500,"SchoolWay Cloud Firestore Data Model","Key collections and identifier-based relationships")
    boxes={
        "users":(80,150,["authUid (PK)","role","email","isActive"]),"students":(430,150,["studentId (PK)","parentAuthUids[]","assignedBusId","assignedRouteId","nfcCardId"]),"buses":(800,150,["busId (PK)","currentDriverUid","assignedRouteId","status","capacity"]),"planned_routes":(1170,150,["routeId (PK)","stops[]","googleGeometry","duration"]),"route_sessions":(1540,150,["sessionId (PK)","driverUid","busId","routeId","status"]),
        "bus_access":(80,610,["busId","member authUid"]),"boarding_events":(430,610,["eventId (PK)","studentId","busId","driverUid","sessionId","eventType"]),"gps_tracking":(800,610,["busId (PK)","driverUid","sessionId","lat/lng","timestamp"]),"notifications":(1170,610,["notificationId (PK)","recipientUid","studentIds[]","read","createdAt"]),"emergency_alerts":(1540,610,["alertId (PK)","driverUid","busId","sessionId","status"]),
        "incidents":(430,1080,["incidentId (PK)","driverUid","busId","severity","resolved"]),"attendance_corrections":(800,1080,["correctionId (PK)","eventId","correctedByUid","reason"]),"route_subcollections":(1170,1080,["breadcrumbs","geofence_events","parent service order"]),
    }
    for name,(x,y,fields) in boxes.items():
        f.rect(x,y,300,260,WHITE,BLUE,14,2)
        f.rect(x,y,300,55,BLUE,BLUE,14,1,name,20,True,WHITE)
        for i,field in enumerate(fields): f.text(x+20,y+85+i*31,field,14,FONT,NAVY,"lt",260)
    rels=[("users","students","parentAuthUids"),("users","buses","currentDriverUid"),("students","buses","assignedBusId"),("students","planned_routes","assignedRouteId"),("buses","planned_routes","assignedRouteId"),("buses","route_sessions","busId"),("users","bus_access","authUid"),("students","boarding_events","studentId"),("route_sessions","boarding_events","sessionId"),("buses","gps_tracking","busId"),("users","notifications","recipientUid"),("route_sessions","emergency_alerts","sessionId"),("boarding_events","attendance_corrections","eventId"),("route_sessions","route_subcollections","sessionId")]
    for a,b,label in rels:
        ax,ay,_=boxes[a]; bx,by,_=boxes[b]
        x1=ax+150; y1=ay+260; x2=bx+150; y2=by
        if by==ay: x1=ax+300; y1=ay+130; x2=bx; y2=by+130
        f.line(x1,y1,x2,y2,GRAY,2,True,"6 4")
        f.text((x1+x2)/2,(y1+y2)/2-10,label,11,FONT,GRAY,"mm",160)
    f.text(1000,1410,"Security rules evaluate Auth UID, role, parent-child link, driver-bus assignment and route-session ownership.",17,BOLD,RED,"mm",1700)
    f.save()


def bar_chart(name,title,subtitle,labels,values,colors,y_label,max_value=None,note=""):
    f=Figure(name,1800,1100,title,subtitle)
    left,top,right,bottom=180,180,1700,880
    f.line(left,top,left,bottom,NAVY,3)
    f.line(left,bottom,right,bottom,NAVY,3)
    mx=max_value or max(values)*1.2 or 1
    for i in range(6):
        val=mx*i/5; y=bottom-(bottom-top)*i/5
        f.line(left,y,right,y,LIGHT_GRAY,1)
        f.text(left-18,y,f"{val:.0f}",14,FONT,GRAY,"rm")
    bw=(right-left)/len(labels)*0.55
    for i,(label,val,color) in enumerate(zip(labels,values,colors)):
        cx=left+(i+0.5)*(right-left)/len(labels)
        bh=(bottom-top)*val/mx
        f.rect(cx-bw/2,bottom-bh,bw,bh,color,color,6,1)
        f.text(cx,bottom-bh-22,f"{val:g}",17,BOLD,NAVY,"mm")
        f.text(cx,bottom+48,label,14,FONT,NAVY,"mm",(right-left)/len(labels)-20)
    f.text(55,(top+bottom)/2,y_label,16,BOLD,NAVY,"mm",140)
    if note: f.text(900,1010,note,15,FONT,GRAY,"mm",1500)
    f.save()


def chapter6_figures():
    bar_chart("Figure_6_1_2_Preliminary_Rendering_Performance","Preliminary Android Frame-Time Sample","Authenticated Admin map screen; 108 frames; development build",["Median","90th percentile","95th percentile","99th percentile"],[5,18,57,200],[GREEN,BLUE,ORANGE,RED],"Frame time (ms)",220,"Diagnostic baseline only: 10 janky frames (9.26%); not a final NFR pass result.")
    bar_chart("Figure_6_2_Test_Execution_Summary","Current Verification Summary","Executed on 28 August 2026",["Flutter tests","Functions tests","Admin smoke screens","Blocked environment checks"],[134,66,3,2],[GREEN,GREEN,BLUE,ORANGE],"Count",150,"Blocked checks: Firestore emulator and release build; both stopped by the host Java loopback error.")
    bar_chart("Figure_6_4_Objectives_Evaluation","Project Objective Evidence Status","Evidence-based assessment before final NFC and moving-GPS validation",["Objective 1: role modules","Objective 2: NFC","Objective 3: GPS tracking"],[90,70,75],[GREEN,ORANGE,ORANGE],"Evidence completion (%)",100,"Percentages are report-planning indicators, not statistical test scores. Objectives 2 and 3 require physical end-to-end evidence.")


def template_chart(name,title,series_labels,x_labels,y_label,note):
    f=Figure(name,1800,1100,title,"Blank measurement template - replace placeholders after testing")
    left,top,right,bottom=180,180,1700,850
    f.line(left,top,left,bottom,NAVY,3); f.line(left,bottom,right,bottom,NAVY,3)
    for i in range(6):
        y=bottom-(bottom-top)*i/5; f.line(left,y,right,y,LIGHT_GRAY,1); f.text(left-20,y,"[value]",13,FONT,GRAY,"rm")
    for i,label in enumerate(x_labels):
        x=left+(i+0.5)*(right-left)/len(x_labels); f.text(x,bottom+45,label,14,FONT,NAVY,"mm",(right-left)/len(x_labels)-15)
        f.line(x,bottom-4,x,bottom+4,NAVY,2)
    f.text(55,(top+bottom)/2,y_label,16,BOLD,NAVY,"mm",140)
    lx=260
    for i,(label,color) in enumerate(zip(series_labels,[BLUE,ORANGE,GREEN,RED,CYAN])):
        f.rect(lx+i*290,930,28,18,color,color,2,1); f.text(lx+38+i*290,939,label,14,FONT,NAVY,"lm",220)
    f.text(900,1030,note,14,FONT,RED,"mm",1550)
    f.save()


def templates():
    template_chart("Figure_6_1_1_Load_Test_Results_TEMPLATE","Load Test Results",["P50 latency","P95 latency","Error rate"],["10 buses","25 buses","50 buses"],"Measured value","Do not submit this blank template as a result. Populate it only after real emulator or staging load tests.")
    template_chart("Figure_6_1_2_Operation_Response_Time_TEMPLATE","Critical Operation Response Times",["Minimum","Mean","P95","Maximum"],["Sign-in","Dashboard","Start session","NFC confirm","GPS display","Notification"],"Response time (ms)","Use at least 10 measured repetitions per operation on a release or profile build.")
    template_chart("Figure_6_1_3_Network_Performance_TEMPLATE","Network Performance Comparison",["GPS display latency","Notification latency","Action recovery time"],["Wi-Fi","Mobile data","Restricted","Reconnect"],"Time (ms)","Record actual connection conditions without including private SSIDs or credentials.")
    template_chart("Figure_6_1_4_Database_Performance_TEMPLATE","Database Operation Performance",["Minimum","Mean","P95","Maximum"],["User read","GPS write","Event write","Report query"],"Response time (ms)","Populate after Firestore emulator or dedicated non-production project testing.")


CAPTIONS = {
    "Figure_3_4_Top_Down_System_Design":"Figure 3.4: Top-down functional decomposition of the SchoolWay mobile application.",
    "Figure_4_1_System_Architecture":"Figure 4.1: Layered system architecture of SchoolWay.",
    "Figure_4_2_Use_Case_Diagram":"Figure 4.2: Use case diagram for Parent, Driver, and Administrator actors.",
    "Figure_4_3_1_Authentication_Role_Routing_Activity":"Figure 4.3.1: Authentication and role-routing activity diagram.",
    "Figure_4_3_2_Admin_Data_Route_Preparation_Activity":"Figure 4.3.2: Administrator data and route-preparation activity diagram.",
    "Figure_4_3_3_Driver_GPS_NFC_Activity":"Figure 4.3.3: Driver route-session, GPS, and NFC activity diagram.",
    "Figure_4_3_4_Parent_Monitoring_Notification_Activity":"Figure 4.3.4: Parent monitoring and notification activity diagram.",
    "Figure_4_3_5_Emergency_Alert_Activity":"Figure 4.3.5: Emergency-alert activity diagram.",
    "Figure_4_4_Firestore_Data_Model":"Figure 4.4: Key Cloud Firestore collections and relationships used by SchoolWay.",
    "Figure_6_1_2_Preliminary_Rendering_Performance":"Figure 6.1.2: Preliminary Android frame-time sample for the authenticated Admin map screen.",
    "Figure_6_2_Test_Execution_Summary":"Figure 6.2: Summary of executed and environment-blocked verification checks.",
    "Figure_6_4_Objectives_Evaluation":"Figure 6.4: Current evidence status for the three project objectives.",
    "Figure_6_1_1_Load_Test_Results_TEMPLATE":"Figure 6.1.1: Load-test results template (pending measured data).",
    "Figure_6_1_2_Operation_Response_Time_TEMPLATE":"Figure 6.1.2: Critical-operation response-time template (pending measured data).",
    "Figure_6_1_3_Network_Performance_TEMPLATE":"Figure 6.1.3: Network-performance comparison template (pending measured data).",
    "Figure_6_1_4_Database_Performance_TEMPLATE":"Figure 6.1.4: Database-performance template (pending measured data).",
}


def manifest():
    lines=["# SchoolWay FYP2 Generated Figures","","Each completed figure is provided as an editable SVG and a high-resolution 300-DPI PNG. Use PNG in Word unless your Word version imports SVG reliably.","","## Completed figures"]
    for name,caption in CAPTIONS.items():
        status="Template - do not report as measured" if "TEMPLATE" in name else "Completed"
        lines += [f"### {caption}",f"- Status: {status}",f"- PNG: `{name}.png`",f"- SVG: `{name}.svg`",""]
    lines += ["## Numbering note","","The current report contains inconsistent Chapter 4/5 figure numbers. Renumber these figures after inserting them and update the List of Figures and all in-text references. The preliminary rendering figure and response-time template both use the provisional 6.1.2 number; retain only the figure that matches the final Chapter 6 structure.",""]
    (OUT/"FIGURE_MANIFEST.md").write_text("\n".join(lines),encoding="utf-8")


if __name__ == "__main__":
    top_down(); architecture(); use_case(); activities(); database(); chapter6_figures(); templates(); manifest()
    print(f"Generated {len(CAPTIONS)} figures in {OUT}")
