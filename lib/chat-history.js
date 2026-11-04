export function normalizeHistory(history){
 if(!Array.isArray(history)||!history.length||history.length>12||history.some(m=>!m||!['user','assistant'].includes(m.role)||typeof m.content!=='string'||!m.content.trim())||history.at(-1).role!=='user')return{error:'The conversation could not be read. Please start a new chat.'};
 if(history.at(-1).content.length>4000)return{error:'Your message is too long. Please use up to 4,000 characters.'};
 const messages=history.slice(-8).map(m=>({role:m.role,content:m.content.slice(0,m.role==='assistant'?12000:4000)}));
 while(messages.length>1&&messages.reduce((n,m)=>n+m.content.length,0)>24000)messages.shift();
 return{messages};
}
