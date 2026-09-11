"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.WordsModule = void 0;
const common_1 = require("@nestjs/common");
const words_controller_1 = require("./words.controller");
const words_service_1 = require("./words.service");
const prisma_module_1 = require("../prisma/prisma.module");
let WordsModule = class WordsModule {
};
exports.WordsModule = WordsModule;
exports.WordsModule = WordsModule = __decorate([
    (0, common_1.Module)({
        imports: [prisma_module_1.PrismaModule],
        controllers: [words_controller_1.WordsController],
        providers: [words_service_1.WordsService],
        exports: [words_service_1.WordsService],
    })
], WordsModule);
//# sourceMappingURL=words.module.js.map