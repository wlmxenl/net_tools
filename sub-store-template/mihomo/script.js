// Sub-Store 脚本参数：name 为要读取的组合订阅/订阅名称
const { name } = $arguments

// 解析 Mihomo YAML 模板内容；文件脚本场景通常来自 $files[0]
const yaml = ProxyUtils.yaml.safeLoad($content ?? $files[0])

// 节点由 Sub-Store 生成并注入，模板内的 proxy-providers 不再需要
delete yaml['proxy-providers']

// 获取 ClashMeta 格式的节点对象数组
let clashMetaProxies = await produceArtifact({
    type: 'collection',
    name: name,
    platform: 'ClashMeta',
    produceType: 'internal'
})

// 清理 Sub-Store 内部字段，避免输出到 Mihomo 配置
function removeUnderscoreFields(obj) {
    if (Array.isArray(obj)) {
        return obj.map(removeUnderscoreFields)
    } else if (typeof obj === 'object' && obj !== null) {
        const newObj = {}
        for (const key in obj) {
            if (!key.startsWith('_')) {
                newObj[key] = removeUnderscoreFields(obj[key])
            }
        }
        return newObj
    }
    return obj
}

clashMetaProxies = removeUnderscoreFields(clashMetaProxies)

// 将 Sub-Store 节点放在模板内置节点前面，保留模板中的直连等静态节点
yaml.proxies = [...clashMetaProxies, ...(yaml.proxies || [])]

// 输出最终 Mihomo YAML
$content = ProxyUtils.yaml.dump(yaml)
