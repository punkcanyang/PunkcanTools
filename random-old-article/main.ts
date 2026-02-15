import { App, Notice, Plugin, PluginSettingTab, Setting, TFile } from 'obsidian';

interface RandomOldArticleSettings {
	cooldownDays: number;
	excludedFolders: string[];
	minFileAgeDays: number;
}

interface FileReadHistory {
	[path: string]: number;
}

const DEFAULT_SETTINGS: RandomOldArticleSettings = {
	cooldownDays: 365,
	excludedFolders: [],
	minFileAgeDays: 30
};

export default class RandomOldArticlePlugin extends Plugin {
	settings!: RandomOldArticleSettings;
	readHistory: FileReadHistory = {};

	async onload() {
		await this.loadSettings();
		await this.loadHistory();

		// 添加ribbon图标
		this.addRibbonIcon('dice', '随机旧文章', () => {
			this.pickRandomArticle();
		});

		// 添加命令
		this.addCommand({
			id: 'pick-random-old-article',
			name: '挑选随机旧文章',
			callback: () => {
				this.pickRandomArticle();
			}
		});

		// 添加设置标签页
		this.addSettingTab(new RandomOldArticleSettingTab(this.app, this));

		// 添加清除历史命令
		this.addCommand({
			id: 'clear-read-history',
			name: '清除阅读历史',
			callback: () => {
				this.clearHistory();
			}
		});
	}

	onunload() {
	}

	async loadSettings() {
		const data = await this.loadData();
		this.settings = { ...DEFAULT_SETTINGS, ...data };
	}

	async saveSettings() {
		await this.saveData(this.settings);
	}

	async loadHistory() {
		const savedHistory = await this.loadData();
		if (savedHistory && savedHistory.history) {
			this.readHistory = savedHistory.history;
		}
	}

	async saveHistory() {
		const data = await this.loadData() || {};
		data.history = this.readHistory;
		await this.saveData(data);
	}

	async clearHistory() {
		this.readHistory = {};
		await this.saveHistory();
		new Notice('阅读历史已清除');
	}

	async pickRandomArticle() {
		const files = await this.getEligibleFiles();
		
		if (files.length === 0) {
			new Notice('没有找到符合条件的文章');
			return;
		}

		// 随机选择一个文件
		const randomIndex = Math.floor(Math.random() * files.length);
		const selectedFile = files[randomIndex];

		// 记录这次选择
		this.readHistory[selectedFile.path] = Date.now();
		await this.saveHistory();

		// 打开文件
		await this.app.workspace.openLinkText(selectedFile.path, '', false);
		
		// 显示通知
		const stats = this.getFileStats(selectedFile);
		new Notice(`已打开: ${selectedFile.basename}\n${stats}`, 5000);
	}

	async getEligibleFiles(): Promise<TFile[]> {
		const now = Date.now();
		const cooldownMs = this.settings.cooldownDays * 24 * 60 * 60 * 1000;
		const minAgeMs = this.settings.minFileAgeDays * 24 * 60 * 60 * 1000;

		const allFiles = this.app.vault.getMarkdownFiles();
		
		const eligibleFiles: TFile[] = [];
		
		for (const file of allFiles) {
			// 检查是否在排除的文件夹中
			let excluded = false;
			for (const excludedFolder of this.settings.excludedFolders) {
				if (file.path.startsWith(excludedFolder)) {
					excluded = true;
					break;
				}
			}
			if (excluded) continue;

			// 检查文件年龄是否足够大
			const fileStat = await this.app.vault.adapter.stat(file.path);
			if (fileStat) {
				const fileAge = now - fileStat.ctime;
				if (fileAge < minAgeMs) {
					continue;
				}
			}

			// 检查是否在冷却期内
			const lastRead = this.readHistory[file.path];
			if (lastRead && (now - lastRead) < cooldownMs) {
				continue;
			}

			eligibleFiles.push(file);
		}
		
		return eligibleFiles;
	}

	getFileStats(file: TFile): string {
		const lastRead = this.readHistory[file.path];
		if (lastRead) {
			const days = Math.floor((Date.now() - lastRead) / (24 * 60 * 60 * 1000));
			return `上次阅读: ${days} 天前`;
		}
		return '从未阅读';
	}
}

class RandomOldArticleSettingTab extends PluginSettingTab {
	plugin: RandomOldArticlePlugin;

	constructor(app: App, plugin: RandomOldArticlePlugin) {
		super(app, plugin);
		this.plugin = plugin;
	}

	async display(): Promise<void> {
		const { containerEl } = this;

		containerEl.empty();

		new Setting(containerEl)
			.setName('冷却期（天）')
			.setDesc('文章被阅读后，多少天内不会再被选中')
			.addSlider(slider => slider
				.setLimits(1, 730, 1)
				.setValue(this.plugin.settings.cooldownDays)
				.setDynamicTooltip()
				.onChange(async (value) => {
					this.plugin.settings.cooldownDays = value;
					await this.plugin.saveSettings();
				}));

		new Setting(containerEl)
			.setName('最小文件年龄（天）')
			.setDesc('只选择创建至少这么多天的文章')
			.addSlider(slider => slider
				.setLimits(0, 365, 1)
				.setValue(this.plugin.settings.minFileAgeDays)
				.setDynamicTooltip()
				.onChange(async (value) => {
					this.plugin.settings.minFileAgeDays = value;
					await this.plugin.saveSettings();
				}));

		new Setting(containerEl)
			.setName('排除的文件夹')
			.setDesc('输入要排除的文件夹路径，每行一个')
			.addTextArea(text => text
				.setPlaceholder('例如：\nTemplates\nDaily Notes\nArchive')
				.setValue(this.plugin.settings.excludedFolders.join('\n'))
				.onChange(async (value) => {
					this.plugin.settings.excludedFolders = value
						.split('\n')
						.map(line => line.trim())
						.filter(line => line.length > 0);
					await this.plugin.saveSettings();
				}));

		// 显示统计信息
		const eligibleFiles = await this.plugin.getEligibleFiles();
		containerEl.createEl('h3', { text: '统计信息' });
		containerEl.createEl('p', { 
			text: `符合条件的文章数量: ${eligibleFiles.length}` 
		});
		
		const historyCount = Object.keys(this.plugin.readHistory).length;
		containerEl.createEl('p', { 
			text: `已记录的历史文章数量: ${historyCount}` 
		});

		// 添加清除历史按钮
		new Setting(containerEl)
			.setName('清除阅读历史')
			.setDesc('重置所有文章的阅读记录')
			.addButton(button => button
				.setButtonText('清除历史')
				.onClick(async () => {
					if (confirm('确定要清除所有阅读历史吗？')) {
						await this.plugin.clearHistory();
						this.display(); // 刷新设置页面
					}
				}));
	}
}
