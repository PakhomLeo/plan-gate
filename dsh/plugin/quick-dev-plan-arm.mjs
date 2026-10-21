/**
 * 快速开发模式的"计划模式自动武装"。
 *
 * 为什么需要它：计划模式在新会话里默认不激活，官方也没有"创建时的计划选项"
 * （fork 继承已记录状态，新起的会话从未激活开始），而模型没有进入计划模式的工具
 * （`/plan` 是用户命令，`exit_plan_mode` 只能退出）。这个模式的确认门就是
 * "提交计划等批准"，所以必须有人在"该交计划"的时候把它打开。
 *
 * 什么时候算该交计划：项目根有项目规则、没有当次说明。首次项目该交设计文档、
 * 每次任务该交当次说明，都落在这一条上；非流程项目、当次说明还在、已批准之后都不开。
 *
 * 不碰工具目录、不拦工具调用、不改任何提示段。
 *
 * 它必须挂在 preset 的 planning 组内部：那个组用 isolate 把 planMode 隔成组内
 * 私有的服务符号，组外的行拿不到这个服务。依赖走模块级 inject（声明式），这样
 * 服务不来时预设注册表会把这行报成 waiting，而不是静默什么都不做。
 */
import { existsSync } from 'node:fs'
import { join } from 'node:path'

export const inject = ['planMode']

/** 项目规则。它在，说明这是个走流程的项目。 */
const RULES_DOC = 'AGENTS.md'
/** 当次说明。它在，说明这次任务已经在确认或施工中。 */
const TASK_DOC = 'TASK.md'

export function apply(ctx) {
  // 见过当次说明的 agent，才在它消失之后重新武装。用 WeakSet 是为了不持有 agent 生命周期。
  const sawTaskDoc = new WeakSet()

  // 子代理绝不武装：退出评审只能由会话根代理打开（子代理调用会被拒），而且子代理
  // 该去干活，不该在这儿提交计划。漏掉这一条会让所有委派任务变成"只出计划"。
  function isSubagent(agent) {
    return agent?.session?.header?.origin === 'subagent'
  }

  function rootOf(agent) {
    const cwd = agent?.session?.header?.cwd
    return typeof cwd === 'string' && cwd !== '' ? cwd : undefined
  }

  /** 计划是这一刻该交的东西：项目规则在，当次说明不在。 */
  function planDue(root) {
    return existsSync(join(root, RULES_DOC)) && !existsSync(join(root, TASK_DOC))
  }

  function arm(agent, reason) {
    const outcome = ctx.planMode.set(agent, true)
    ctx.logger.info('quick-dev: 武装计划模式（%s）→ %s', reason, outcome)
  }

  // agent/created 的契约是"监听器抛错就让整个会话创建失败"，所以这里任何失败
  // 都只能吞掉并记一条警告——绝不能因为武装失败而让人开不了会话。
  ctx.on('agent/created', ({ agent }) => {
    try {
      if (isSubagent(agent)) return
      if (ctx.planMode.get(agent).active) return
      const root = rootOf(agent)
      if (root === undefined || !planDue(root)) return
      arm(agent, '该交计划')
    } catch (error) {
      ctx.logger.warn('quick-dev: 开局武装计划模式失败，本次跳过：%o', error)
    }
  })

  // 重新武装只在"见过当次说明、之后它消失"时发生，所以既不会在对话中途反复重判，
  // 也不会撞上正在进行的确认流程。
  ctx.on('agent/pre-step', ({ agent }, next) => {
    try {
      if (isSubagent(agent)) return next()
      const root = rootOf(agent)
      if (root === undefined) return next()
      if (existsSync(join(root, TASK_DOC))) {
        sawTaskDoc.add(agent)
      } else if (sawTaskDoc.has(agent) && !ctx.planMode.get(agent).active && planDue(root)) {
        sawTaskDoc.delete(agent)
        arm(agent, '上一个任务已收工')
      }
    } catch (error) {
      ctx.logger.warn('quick-dev: 重新武装计划模式失败，本次跳过：%o', error)
    }
    return next()
  })
}