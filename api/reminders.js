import {createClient} from '@supabase/supabase-js';
export default async function handler(req,res){
if(!process.env.CRON_SECRET||req.headers.authorization!==`Bearer ${process.env.CRON_SECRET}`)return res.status(401).json({error:'Unauthorized'});
const{SUPABASE_SERVICE_ROLE_KEY,RESEND_API_KEY,APP_URL}=process.env;
if(!SUPABASE_SERVICE_ROLE_KEY||!RESEND_API_KEY||!APP_URL)return res.status(503).json({error:'Email configuration incomplete'});
const db=createClient('https://izahgrueboaiagbwsalk.supabase.co',SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false}});
const{data:staff,error:se}=await db.from('arks_staff').select('email,active');const{data:tasks,error:te}=await db.from('arks_obligations').select('*');if(se||te)return res.status(500).json({error:'Unable to load reminders'});
const today=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'});let sent=0,failed=0;
for(const task of tasks){const r=task.data;if(!task.owner_email||!staff.some(s=>s.active&&s.email===task.owner_email)||!r.due||['Completed','Not applicable'].includes(r.status))continue;
const date=new Date(r.due);if(isNaN(date))continue;const days=Math.round((Date.UTC(date.getFullYear(),date.getMonth(),date.getDate())-Date.parse(today+'T00:00:00Z'))/86400000);if(![30,14,7,1,0].includes(days)&&days>=0)continue;
const key=`${task.ref}:${r.period}:${r.due}:${task.owner_email}:${today}`;
const{data:prior}=await db.from('arks_email_log').select('id,status').eq('reminder_key',key).maybeSingle();if(prior&&prior.status!=='failed')continue;
if(prior){const{data}=await db.from('arks_email_log').update({status:'pending'}).eq('id',prior.id).eq('status','failed').select('id');if(!data?.length)continue}else{const{error}=await db.from('arks_email_log').insert({obligation_ref:task.ref,recipient:task.owner_email,reminder_key:key});if(error)continue}
try{const response=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${RESEND_API_KEY}`,'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify({from:'ARKS Holding LTD <ahmed@arks.ae>',to:task.owner_email,subject:`ARKS Holding LTD · ${task.ref} ${days<0?'overdue':days===0?'due today':`due in ${days} days`}`,text:`${r.entity}\n${r.title}\nDeadline: ${r.due}\nPlease review your assigned obligation in ARKS Holding LTD.\n${APP_URL}\n\nThis is an automated compliance reminder.`})});if(!response.ok)throw Error('Delivery failed');const result=await response.json();await db.from('arks_email_log').update({status:'sent',provider_id:result.id}).eq('reminder_key',key);sent++}catch{await db.from('arks_email_log').update({status:'failed'}).eq('reminder_key',key);failed++}}
return res.status(200).json({sent,failed});}
