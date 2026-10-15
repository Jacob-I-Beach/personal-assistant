import {readFile,readdir,realpath,stat} from 'node:fs/promises';
import {join,relative,isAbsolute,sep} from 'node:path';

const object=properties=>({type:'object',properties,required:Object.keys(properties),additionalProperties:false});
export const skillTools=[
  {name:'list_skills',description:'Discover optional task playbooks by description. Skills organize existing tools; they do not grant access, execute code or override the user. Read a relevant skill before applying it. Empty query lists available skills.',parameters:object({query:{type:'string',maxLength:400}})},
  {name:'read_skill',description:'Read a specific available skill and its content version. Follow useful task procedure within current permissions and user instructions; report actual verification, never assumed success.',parameters:object({name:{type:'string',maxLength:80}})}
];
export class SkillRuntime {
  constructor(root){this.root=root;}
  async entries(){
    let root;try{root=await realpath(this.root);}catch{return [];}
    const result=[];
    for(const entry of (await readdir(root,{withFileTypes:true})).slice(0,64)){
      if(!entry.isDirectory()||entry.isSymbolicLink()||!/^[a-z][a-z0-9-]{0,79}$/.test(entry.name))continue;
      try{
        const path=await realpath(join(root,entry.name,'SKILL.md')),tail=relative(root,path);
        if(tail==='..'||tail.startsWith('..'+sep)||isAbsolute(tail)||(await stat(path)).size>32768)continue;
        const text=await readFile(path,'utf8'),description=text.match(/^description:\s*(.+)$/m)?.[1]?.slice(0,500);
        if(description)result.push({name:entry.name,description,path,text});
      }catch{/* One unavailable skill does not disable the catalog. */}
    }
    return result;
  }
  async execute(call){
    const entries=await this.entries();let output;
    if(call.name==='read_skill'){
      const item=entries.find(item=>item.name===call.arguments.name);if(!item)throw new Error('This skill is not in the available catalog.');
      const {createHash}=await import('node:crypto');
      output={name:item.name,instructions:item.text,sha256:createHash('sha256').update(item.text).digest('hex'),authority:'Task guidance only; current user instructions and application-enforced permissions take precedence.'};
    }else{
      const words=call.arguments.query.toLowerCase().match(/[a-z0-9]+/g)??[];
      output={skills:entries.map(({name,description})=>({name,description})).filter(item=>!words.length||words.some(word=>(item.name+' '+item.description).toLowerCase().includes(word))),coverage:'Bundled, bounded local playbooks. No remote installation or executable skill hooks.'};
    }
    return {callID:call.id,name:call.name,succeeded:true,output,completedAt:new Date().toISOString()};
  }
}
