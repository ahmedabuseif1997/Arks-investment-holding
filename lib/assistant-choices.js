// Choice IDs are model suggestions; labels and access always come from current records.
export function taskChoiceRefs(value,tasks){if(!Array.isArray(value))return[];const allowed=new Set(tasks.map(t=>t.ref));return [...new Set(value.filter(ref=>typeof ref==='string'&&allowed.has(ref)))].slice(0,8)}
