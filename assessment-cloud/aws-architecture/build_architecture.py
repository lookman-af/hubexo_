from pathlib import Path
import math
import copy
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.graphics.shapes import Drawing, Rect, String, Line, Polygon, Group
from reportlab.graphics import renderPDF, renderSVG
from svglib.svglib import svg2rlg
import fitz

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'output/pdf'
TMP = ROOT / 'tmp/pdfs'
OUT.mkdir(parents=True, exist_ok=True)
TMP.mkdir(parents=True, exist_ok=True)
W, H = landscape(A4)
INK = colors.HexColor('#172B45')
MUTED = colors.HexColor('#506176')
BLUE = colors.HexColor('#1877B8')
PURPLE = colors.HexColor('#7952AD')
GREEN = colors.HexColor('#287D68')
LIGHT = colors.HexColor('#F3F6FA')
BORDER = colors.HexColor('#CAD4E0')
ORANGE = colors.HexColor('#EB8A23')

class Diagram:
    def __init__(self, height=350):
        self.h = height
        self.d = Drawing(770, height)
    def box(self,x,y,w,h,fill=colors.white,stroke=BORDER,dash=None):
        self.d.add(Rect(x,self.h-y-h,w,h,fillColor=fill,strokeColor=stroke,strokeWidth=.8,strokeDashArray=dash))
    def text(self,x,y,s,size=9,bold=False,color=INK):
        self.d.add(String(x,self.h-y-size,s,fontName='Helvetica-Bold' if bold else 'Helvetica',fontSize=size,fillColor=color))
    def icon(self,name,x,y,size=28):
        icon=svg2rlg(str(HERE/'assets'/f'{name}.svg'))
        g=Group()
        g.add(icon)
        g.scale(size/icon.width,size/icon.height)
        g.translate(x*icon.width/size,(self.h-y-size)*icon.height/size)
        self.d.add(g)
    def arrow(self,pts,color=BLUE,dash=None,head=True):
        for a,b in zip(pts,pts[1:]):
            self.d.add(Line(a[0],self.h-a[1],b[0],self.h-b[1],strokeColor=color,strokeWidth=1.1,strokeDashArray=dash))
        if head:
            a,b=pts[-2:]
            ang=math.atan2(b[1]-a[1],b[0]-a[0])
            p=[b[0],self.h-b[1]]
            for v in [-.45,.45]:
                p += [b[0]-5*math.cos(ang+v),self.h-(b[1]-5*math.sin(ang+v))]
            self.d.add(Polygon(p,fillColor=color,strokeColor=color))
    def account(self,x,y,w,title,sub,icon=None,h=49):
        self.box(x,y,w,h)
        off=9
        if icon:
            self.icon(icon,x+8,y+11,25); off=41
        self.text(x+off,y+8,title,9,True)
        for i,s in enumerate(sub): self.text(x+off,y+22+i*11,s,8,color=MUTED)

def landing():
    q=Diagram(350)
    q.box(0,0,770,61,LIGHT,INK)
    q.icon('AWS-Organizations',12,13,32)
    q.text(53,10,'AWS Organizations',12,True)
    q.text(53,29,'Management account | billing + governance',8.4)
    q.icon('AWS-Control-Tower',312,13,32)
    q.text(352,10,'AWS Control Tower',11,True)
    q.text(352,29,'Landing zone + enrolled OUs + controls',8.4)
    q.icon('AWS-IAM-Identity-Center',582,13,32)
    q.text(622,10,'IAM Identity Center',10,True)
    q.text(622,29,'Corporate IdP / MFA / roles',8.4)
    q.arrow([(385,61),(385,74)],INK,head=False)
    q.arrow([(72,74),(619,74)],INK,head=False)
    for x in [72,228,384,619]: q.arrow([(x,74),(x,86)],INK)
    for x,w,title in [(0,145,'Security OU'),(156,145,'Infrastructure OU'),(312,145,'Platform OU'),(468,302,'Workloads OU')]:
        q.box(x,86,w,204 if x==468 else 152,LIGHT)
        q.text(x+10,94,title,10.5,True)
    q.account(7,117,131,'Log Archive',['CloudTrail / Config','S3 + protected retention'],'Amazon-Simple-Storage-Service')
    q.account(7,177,131,'Audit / Security',['GuardDuty','Security Hub / admin'],'AWS-Security-Hub')
    q.account(163,117,131,'Network account',['TGW / DNS / IPAM','Firewall / egress'],'AWS-Transit-Gateway')
    q.account(163,177,131,'Observability',['Cross-account visibility','SLOs / dashboards'],'Amazon-CloudWatch')
    q.account(319,117,131,'AFT management',['Account vending'],h=35)
    q.account(319,157,131,'Delivery account',['CI/CD + artifacts'],h=35)
    q.account(319,197,131,'AI tooling account',['Sandbox + tool gateway'],h=35)
    q.text(480,114,'Accounts repeated per product / domain',9,color=MUTED)
    for x,y,title,sub in [(480,134,'Development account',['Synthetic data / TTL']), (625,134,'Test account',['Integration / contracts']), (480,194,'Staging account',['Prod-like / release tests']), (625,194,'Production account',['Multi-AZ / controlled DR'])]:
        q.account(x,y,133,title,sub,h=49)
    q.text(480,259,'Child OUs group common controls by environment.',8.7)
    q.text(480,273,'No implicit network trust between accounts.',8.7)
    for x,title,sub in [(0,'Sandbox OU','Experiments / no prod access'),(156,'Policy Staging OU','Test guardrail changes'),(312,'Suspended OU','Restricted / incident isolation')]:
        q.box(x,250,145,40,colors.white,ORANGE)
        q.text(x+9,256,title,9,True)
        q.text(x+9,271,sub,8,color=MUTED)
    q.box(0,309,770,37,colors.HexColor('#F0F7F5'),GREEN)
    q.icon('AWS-CloudTrail',10,315,23)
    q.icon('AWS-Config',39,315,23)
    q.text(73,315,'Enrolled accounts: audit / configuration logs -> Log Archive; findings -> Audit; telemetry -> Observability',9,True)
    q.text(73,330,'Logical governance diagram. Lines show hierarchy; runtime networking is shown separately on page 2.',8,color=MUTED)
    return q.d

def workload():
    q=Diagram(352)
    q.account(0,0,117,'Global users',['HTTPS application traffic'],h=46)
    q.account(155,0,165,'Amazon CloudFront',['Public entry / TLS'],'Amazon-CloudFront',46)
    q.account(355,0,149,'AWS WAF',['Web ACL on CloudFront'],'AWS-WAF',46)
    q.arrow([(117,23),(155,23)])
    q.arrow([(355,23),(320,23)],PURPLE,[3,3],head=False)
    q.icon('Amazon-Route-53',9,53,23)
    q.text(40,54,'Route 53: DNS alias to CloudFront',8.5)
    q.arrow([(40,74),(236,74),(236,46)],PURPLE,[3,3])
    q.account(538,0,232,'Amazon EKS control plane',
              ['AWS-managed / private API endpoint'],
              'Amazon-Elastic-Kubernetes-Service',h=54)
    q.box(0,85,517,239,LIGHT,INK)
    q.text(11,91,'Production account | Region A | VPC',10,True)
    q.account(183,111,154,'Internal ALB',['CloudFront VPC origin'],'Elastic-Load-Balancing',46)
    q.arrow([(266,46),(266,111)])
    q.text(275,68,'Private origin connection',8.4,color=BLUE)
    for x,title in [(14,'Availability Zone A'),(268,'Availability Zone B')]:
        q.box(x,174,235,137,colors.white,GREEN,[4,2])
        q.text(x+9,180,title,9,True)
        q.icon('Amazon-EC2',x+10,202,27)
        q.text(x+46,200,'EKS worker nodes / application pods',8.6,True)
        q.text(x+46,214,'Private subnet / EKS Pod Identity',8.2)
        q.icon('Amazon-Aurora',x+10,261,27)
        q.text(x+46,259,'Aurora writer' if x==14 else 'Aurora reader / failover',9,True)
        q.text(x+46,274,'Isolated DB subnet / cluster endpoint',8.2)
        q.arrow([(x+118,229),(x+118,252)])
    q.arrow([(230,157),(230,165),(132,165),(132,198)])
    q.arrow([(290,157),(290,165),(386,165),(386,198)])
    q.arrow([(245,285),(269,285)],PURPLE,[3,3])
    q.text(197,297,'One Aurora cluster',8,color=MUTED)
    q.box(538,85,232,116,LIGHT)
    q.text(548,92,'Primary-region managed services',9.5,True)
    q.icon('AWS-Secrets-Manager',550,114,26)
    q.text(585,114,'Secrets Manager + AWS KMS',9,True)
    q.text(585,128,'Service account -> Pod Identity role',8.2)
    q.icon('Amazon-Simple-Storage-Service',550,153,26)
    q.text(585,152,'Amazon S3 / private endpoints',9,True)
    q.text(585,167,'Artifacts, objects and service access',8.2)
    q.text(549,186,'Endpoint policies + least-privilege IAM',8.2,color=MUTED)
    q.arrow([(503,218),(527,218),(527,142),(538,142)],BLUE)
    q.box(538,226,232,98,colors.HexColor('#FFF8EC'),ORANGE,[4,3])
    q.text(550,233,'Production account | DR region',10,True)
    q.icon('Amazon-Aurora',550,256,26)
    q.text(585,254,'Aurora Global Database secondary',8.7,True)
    q.text(585,268,'Separate EKS cluster / warm capacity',8.4)
    q.text(550,295,'Promote DB + scale app + switch origin',8.5)
    q.arrow([(503,281),(538,281)],PURPLE,[3,3])
    q.text(550,211,'Cross-region asynchronous replication',8,color=PURPLE)
    q.arrow([(538,38),(520,38),(520,205),(503,205)],PURPLE,[3,3])
    q.text(0,337,'Blue: application traffic     Purple dashed: management / DNS / replication     One regional EKS cluster spans the worker AZs.',8.5,color=MUTED)
    return q.d

body = ParagraphStyle('body',fontName='Helvetica',fontSize=10,leading=14,textColor=INK,spaceAfter=6)
small = ParagraphStyle('small',parent=body,fontSize=8.5,leading=11)
heading = ParagraphStyle('heading',parent=body,fontName='Helvetica-Bold',fontSize=12,leading=16,spaceAfter=6)
c=canvas.Canvas(str(OUT/'aws-control-tower-architecture.pdf'),pagesize=(W,H))
c.setTitle('AWS Cloud Platform - Architecture Design')
c.setAuthor('Architecture assessment')

def para(text,x,top,w,style=body):
    p=Paragraph(text,style); _,h=p.wrap(w,H)
    p.drawOn(c,x,H-top-h)
    return top+h

def base(n,title,subtitle):
    c.setFillColor(INK); c.rect(0,H-9,W,9,fill=1,stroke=0)
    c.setFont('Helvetica-Bold',9); c.drawString(36,H-33,'ARCHITECTURE DESIGN  /  AWS CLOUD PLATFORM')
    c.setFillColor(INK); c.setFont('Helvetica-Bold',23); c.drawString(36,H-63,title)
    para(subtitle,36,74,W-72,small)
    c.setStrokeColor(BORDER); c.line(36,32,W-36,32)
    c.setFillColor(MUTED); c.setFont('Helvetica',8)
    c.drawRightString(W-36,19,f'{n} / 4')

base(1,'Governed landing zone, autonomous product teams','Shared governance and account foundations; applications run in isolated product and environment accounts. [1-4]')
d1=landing(); renderPDF.draw(d1,c,36,H-111-350)
para('<b>Design decision.</b> AWS Control Tower establishes a landing zone on AWS Organizations. The management account is reserved for governance. The Security OU separates audit storage from security tooling. OUs group common controls; accounts provide isolation, independent quotas, and cost attribution.',36,476,W-72,body)
para('Use separate Development, Test, Staging, and Production accounts per product or domain. Size account boundaries by ownership and risk, not engineer count. Each environment has its own EKS cluster and data. Platform automation provisions and enrolls additional OUs/accounts; Control Tower does not create the application platform automatically.',36,523,W-72,small)
c.showPage()

base(2,'Amazon EKS: private workloads, multi-AZ resilience','Managed Kubernetes control plane with EC2 workers in private subnets. Two worker AZs are shown; use additional AZs where required. [5,8-10]')
d2=workload(); renderPDF.draw(d2,c,36,H-108-352)
para('<b>Request path.</b> Route 53 resolves the CloudFront domain. AWS WAF protects CloudFront; a private VPC origin connects to the internal ALB. AWS Load Balancer Controller manages Ingress and registers pod IP targets. Pods use Aurora writer/reader endpoints as appropriate and EKS Pod Identity for AWS service access.',36,474,W-72,body)
para('<b>Control and recovery.</b> The EKS API is private and reached through approved network paths. The control plane manages workers; it does not carry application traffic. Multi-AZ protects against zonal failure. Regional recovery requires a separate EKS cluster, database promotion, and a controlled origin switch; it is not automatic write failover.',36,518,W-72,small)
c.showPage()

base(3,'Architecture decisions and operating boundaries','Security, networking, Kubernetes operations, reliability, and cost decisions. Numerical recovery targets remain assessment assumptions.')
col=(W-96)/2
def section(x,y,title,text):
    y=para(title,x,y,col,heading)
    return para(text,x,y+2,col,body)+16
y=113
y=section(36,y,'01  Account vending and governance',
    'The developer portal opens an account-request PR with owner, cost center, data classification, and environment. AFT provisions and customizes accounts from its dedicated account. Separate pipelines deploy EKS infrastructure and applications. Versioned templates configure baseline IAM, logging, network controls, and metadata. Test policy changes in the Policy Staging OU before rollout. [1,3]')
y=section(36,y,'02  Identity and security boundaries',
    'Federate IAM Identity Center to the corporate IdP with MFA. Use EKS access entries and scoped Kubernetes RBAC; production elevation requires time-limited approval. SCPs limit maximum permissions, grant no access, and exclude the management account. Run Terraform policy checks separately from CloudFormation-based proactive controls. Use Pod Identity per service account; restrict node-role/IMDS access. Enforce Pod Security Admission and default-deny NetworkPolicy with a supporting CNI. [4,10,11]')
y=section(36,y,'03  Private networking and ingress',
    'The Network account owns IPAM, DNS Resolver, TGW, and inspected egress. Separate production/nonproduction routing; no implicit cross-environment access. Use SGs between tiers, endpoint policies, and VPC CNI IP-capacity planning. Private EKS endpoints require reachable DNS/network paths for runners and operators. CloudFront VPC origins require supported regions/protocols and an attached internet gateway, but no public route to the origin subnet. [5,9]')
yr=113
yr=section(W/2+12,yr,'04  EKS capacity and lifecycle',
    'Use an On-Demand managed node group for system controllers and Karpenter NodePools for application capacity. HPA scales pods; Karpenter scales its EC2 nodes. Define resource requests/limits, topology spread, readiness/startup probes, and PodDisruptionBudgets. PDBs limit voluntary disruption, not AZ failures. Test EKS, add-on, node-image, and controller upgrades in Staging before rolling or blue/green production upgrades. [8]')
yr=section(W/2+12,yr,'05  Availability and regional recovery',
    'Spread replicas across worker AZs and retain spare capacity. Use Aurora writer/reader instances across AZs. Example critical-tier targets: SLO 99.9%, RTO 60 minutes, RPO 15 minutes. Prepare a separate regional EKS cluster, replicated ECR images, manifests, secrets, and Aurora Global Database secondary. Test database promotion, traffic switching, and restores; use cross-account backups. Validate region/engine support and replication lag. [6]')
yr=section(W/2+12,yr,'06  Ownership and cost management',
    'Platform teams own cluster lifecycle and approved add-ons; product teams own workloads, SLOs, on-call, and cost. Each environment has separate IAM roles, secrets, data, and IaC state. Namespaces organize trusted workloads; they do not replace account/cluster isolation. Track EKS control-plane, EC2, NAT, endpoint, logging, and DR costs. Use quotas, rightsizing, TTL, and interruption-tolerant Spot capacity; budget alerts are not spending caps. [7]')
assert max(y,yr)<560,(y,yr)
c.showPage()

base(4,'Environment strategy and governed delivery','Consistent platform controls with progressively stronger access, capacity, and release assurance toward production.')
rows=[['Environment','Data and access','Deployment and reliability'],
['Development','Synthetic data; scoped developer access','Automated builds; namespace TTL; small capacity'],
['Test','Synthetic/masked data; separate identities','Integration, contract, and negative security tests'],
['Staging','Masked data; production-like EKS configuration','Load, DAST, upgrade, rollback, and multi-AZ tests'],
['Production','Business data; least privilege; temporary elevation','Protected release gates; multi-AZ; tier-based DR']]
table=Table([[Paragraph(s,small) for s in row] for row in rows],colWidths=[102,285,W-72-387],rowHeights=[25,28,28,28,28])
table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),INK),('ROWBACKGROUNDS',(0,1),(-1,-1),[LIGHT,colors.white]),('VALIGN',(0,0),(-1,-1),'MIDDLE'),('LEFTPADDING',(0,0),(-1,-1),9),('RIGHTPADDING',(0,0),(-1,-1),9),('LINEBELOW',(0,0),(-1,-1),.4,BORDER)]))
for i,s in enumerate(rows[0]): table._cellvalues[0][i]=Paragraph('<font color="white"><b>'+s+'</b></font>',small)
table.wrap(W-72,H); table.drawOn(c,36,H-108-137)
left=36; right=W/2+12
para('Kubernetes delivery and observability',left,257,col,heading)
para('Build once; run tests, SAST/SCA, secret/IaC/image scans, and generate an SBOM. Sign images in ECR and promote the same digest with versioned Helm/Kustomize manifests. A scoped GitOps controller per cluster reconciles approved releases. Gate production on artifact/plan/target approval and SLO checks; roll back manifests/images separately from database migrations.',left,279,col,small)
para('Collect pod/node metrics, application logs, and OpenTelemetry traces. Enable EKS control-plane/audit logs; CloudTrail does not capture every Kubernetes API action. Central dashboards show SLOs, owner, deployments, and cost. Protect audit retention, redact sensitive data, and route actionable alerts to the service owner.',left,346,col,small)
para('AI agents: controlled execution',right,257,col,heading)
para('Run agents in the isolated AI tooling account with short-lived role sessions, a sandbox, and an external policy-enforcing tool gateway. Agents may create code/PRs but cannot approve their own changes, grant IAM/RBAC privileges, or bypass admission policies. Production and destructive actions require approval bound to the exact action and target.',right,279,col,small)
para('Record requester, agent/task ID, approval, tool call, Kubernetes/cloud target, outcome, and cost. Emergency controls block the gateway, stop jobs, isolate networking, and revoke supported sessions. Removing a trust policy alone does not invalidate all active sessions. Apply cost/time limits, egress allowlists, and sensitive-data redaction.',right,346,col,small)
para('Official references and design assumptions',36,413,W-72,heading)
sources=[
('1','Control Tower: account structure','https://docs.aws.amazon.com/prescriptive-guidance/latest/designing-control-tower-landing-zone/account-structure.html'),
('2','AWS Architecture Icons','https://aws.amazon.com/architecture/icons/'),
('3','AFT overview and scope','https://docs.aws.amazon.com/controltower/latest/userguide/aft-overview.html'),
('4','Control Tower control behavior','https://docs.aws.amazon.com/controltower/latest/controlreference/control-behavior.html'),
('5','CloudFront private VPC origins','https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html'),
('6','Aurora Global Database','https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html'),
('7','AWS Well-Architected Framework','https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html'),
('8','EKS application reliability / scaling','https://docs.aws.amazon.com/eks/latest/best-practices/application.html'),
('9','EKS load balancing','https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html'),
('10','EKS Pod Identity','https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html'),
('11','EKS security best practices','https://docs.aws.amazon.com/eks/latest/best-practices/security.html'),
]
refcol=(W-96)/3
for i,(n,label,url) in enumerate(sources):
    column=i//4; row=i%4
    para(f'[{n}] <link href="{url}" color="#1877B8">{label}</link>',36+column*(refcol+12),437+row*14,refcol,small)
para('Assumptions: containerized web/API workloads; regions, residency, traffic, and business SLAs are not yet agreed. This high-level design requires detailed routing, backup, EKS sizing, and deployment validation. Official icons do not imply AWS certification or endorsement.',36,508,W-72,small)
c.showPage(); c.save()
renderSVG.drawToFile(d1,str(HERE/'aws-landing-zone.svg'))
renderSVG.drawToFile(d2,str(HERE/'aws-production-workload.svg'))
doc=fitz.open(OUT/'aws-control-tower-architecture.pdf')
assert len(doc)==4
for i,p in enumerate(doc):
    p.get_pixmap(matrix=fitz.Matrix(1.6,1.6),alpha=False).save(TMP/f'aws-architecture-page-{i+1}.png')
print('Created 4-page PDF, 2 vector diagrams, and QA renders.')
